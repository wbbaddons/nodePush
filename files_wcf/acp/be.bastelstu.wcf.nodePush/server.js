/*
 *  Copyright (C) 2012 - 2016 Tim Düsterhus
 *
 *  This program is free software: you can redistribute it and/or modify
 *  it under the terms of the GNU Affero General Public License as published by
 *  the Free Software Foundation, either version 3 of the License, or
 *  (at your option) any later version.
 *
 *  This program is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU Affero General Public License for more details.
 *
 *  You should have received a copy of the GNU Affero General Public License
 *  along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */
"use strict";

if ((process.getuid && process.getuid() === 0) || (process.getgid && process.getgid() === 0)) {
	throw new Error('Cowardly refusing to keep the process alive as root')
}

process.chdir(__dirname)

const crypto       = require('crypto')
const debug        = require('debug')('nodePush')
const escapeRegExp = require('escape-string-regexp')
const express      = require('express')
const redis        = require('redis')

let io = null

const config = require('rc')('nodePush', { enableStats: false
                                         , outbound: { port: 9001
                                                     , host: '0.0.0.0'
                                                     }
                                         , signerKey: null
                                         , uuid: null
                                         , redis: 'redis://localhost'
                                         })

const REKEY_INTERVAL = 60

process.title = `nodePush ${config.outbound.host}:${config.outbound.port}`

if (!config.signerKey) {
	throw new Error('Please specify the secret key of WSC')
}

if (!config.uuid) {
	throw new Error('Please specify the UUID of WSC')
}

const stats = { outbound: { total: 0
                          , current: 0
                          }
              , inbound: 0
              , bootTime: new Date()
              }
if (config.enableStats) stats.messages = { }

function checkSignature(data, key) {
	let [ signature, payload ] = String(data).split(/-/)

	if (!payload) {
		return false
	}

	payload = new Buffer(payload, 'base64')
	if (signature.length !== 64) {
		return false
	}

	const hmac = crypto.createHmac('sha256', key)
	hmac.update(payload)
	const digest = hmac.digest('hex')

	// https://www.isecpartners.com/blog/2011/february/double-hmac-verification.aspx
	const given = crypto.createHmac('sha256', key)
	given.update(signature)

	const calculated = crypto.createHmac('sha256', key)
	calculated.update(digest)

	if (given.digest('hex') !== calculated.digest('hex')) {
		return false
	}

	return payload
}

function sendMessage(name, target, payload) {
	if (!/^[a-zA-Z0-9-_]+\.[a-zA-Z0-9-_]+(\.[a-zA-Z0-9-_]+)+$/.test(name)) return false

	debug(`${name} -> ${JSON.stringify(target)}`)

	if (config.enableStats) {
		stats.messages[name] = (stats.messages[name] || 0) + 1
	}

	if (target == null) {
		io.to('authenticated').emit(name, payload)
		return
	}
	if (target.registered) {
		io.to('registered')
	}
	if (target.guest) {
		io.to('guest')
	}
	if (target.users instanceof Array) {
		target.users.forEach(userID => io.to(`user-${userID}`))
	}
	if (target.groups instanceof Array) {
		target.groups.forEach(groupID => io.to(`group-${groupID}`))
	}
	if (target.channels instanceof Array) {
		target.channels.forEach(channel => io.to(`channel-${channel}`))
	}

	io.emit(name, payload)

	return true
}

const app = express()
app.use(require('cors')())

const server = require('http').Server(app)

app.get('/status', function (req, res) {
	res.charset = 'utf-8'
	res.type('json')
	res.send(JSON.stringify(stats))
})

{
	const sourceFiles = [ 'server.js'
	                    , 'package.json'
	                    , 'Dockerfile'
	                    , 'LICENSE'
	                    ]

	app.get('/source', function (req, res) {
		res.charset = 'utf-8'
		res.type('txt')

		res.send(`# nodePush

The following source files are available for download:
${sourceFiles.map((item) => `* /source/${item}`).join('\n')}`)
	})

	app.get(new RegExp('/source/('+sourceFiles.map(escapeRegExp).join('|')+')'), function (req, res) {
		res.type('txt').sendFile(`${__dirname}/${req.params[0]}`, function (err) {
			if (err) {
				if (err.code !== 'ECONNABORT' || res.statusCode !== 304) {
					if (!res.headersSent) {
						res.sendStatus(404)
					}
				}

				res.end()
			}
		})
	})
}

server.listen(config.outbound.port, config.outbound.host, null, function () {
	const rsub = redis.createClient(config.redis)
	const r = redis.createClient(config.redis)
	
	io = require('socket.io')(server)

	io.on('connection', function (socket) {
		const id = ++stats.outbound.total
		stats.outbound.current++

		debug(`Client ${id} connected`)
		
		let channels
		let rekeyTimer = undefined
		let rekey = function () {
			debug(`Client ${id} (${JSON.stringify(channels)}) receiving new keys`)
			crypto.randomBytes(32, function (err, buf) {
				if (err) {
					socket.disconnect()
					return
				}
				r.set(`${config.uuid}:nodePush:token:${buf.toString('hex')}`, JSON.stringify(channels), 'EX', REKEY_INTERVAL * 3)
				socket.emit('rekey', buf.toString('hex'))
			})
		}
		let connected = function () {
			rekey()
			rekeyTimer = setInterval(rekey, REKEY_INTERVAL * 1e3)
			socket.emit('authenticated')
		}

		socket.on('disconnect', function () {
			debug(`Client ${id} disconnected`)

			stats.outbound.current--
			clearInterval(rekeyTimer)
		})

		socket.on('connectData', function (connectData) {
			debug(`Client ${id} sent connectData ${connectData}`)

			let payload

			if (!(payload = checkSignature(connectData, config.signerKey))) {
				socket.disconnect()
				return
			}
			debug(`Client ${id} connectData: ${payload.toString('utf8')}`)
			payload = JSON.parse(payload.toString('utf8'))
			if (!payload.timestamp || (payload.timestamp * 1000) < (Date.now() - 15e3)) {
				socket.disconnect()
				return
			}
			payload.userID = parseInt(payload.userID, 10)
			if (!(payload.groups instanceof Array)) {
				socket.disconnect()
				return
			}
			if (!(payload.channels instanceof Array)) {
				socket.disconnect()
				return
			}

			channels = [ 'authenticated' ]
			channels.push(`user-${payload.userID}`)
			if (payload.userID === 0) {
				channels.push('guest')
			}
			else {
				channels.push('registered')
			}
			payload.groups.forEach(groupID => channels.push(`group-${groupID}`))
			payload.channels.forEach(channel => channels.push(`channel-${channel}`))
			
			channels.forEach(channel => socket.join(channel))
			connected()
		})
		
		socket.on('token', function (token) {
			debug(`Client ${id} sent reconnect token ${token}`)
			r.get(`${config.uuid}:nodePush:token:${token}`, function (err, reply) {
				r.del(`${config.uuid}:nodePush:token:${token}`)
				if (err) {
					socket.disconnect()
					return
				}
				if (reply === null) {
					socket.disconnect()
					return
				}
				
				try {
					channels = JSON.parse(reply)
					channels.forEach(channel => socket.join(channel))
					
					connected()
				}
				catch (e) {
					socket.disconnect()
					return
				}
			})
		})
	})

	rsub.on('message', function (channel, _message) {
		stats.inbound++
		if (channel === `${config.uuid}:nodePush`) {
			debug(`Push: ${_message}`)
			try {
				_message = JSON.parse(_message)
			}
			catch (e) {
				debug(`Error parsing JSON: ${e}`)
				return
			}

			if (!_message.message) return

			const message = _message.message
			const target  = _message.target
			const payload = _message.payload

			sendMessage(message, target, payload)
		}
	})

	rsub.subscribe(`${config.uuid}:nodePush`)
})
