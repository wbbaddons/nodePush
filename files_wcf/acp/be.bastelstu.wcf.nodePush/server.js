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

if ((process.getuid && process.getuid() === 0) || (process.getgid() && process.getgid() === 0)) {
	throw new Error('Cowardly refusing to keep the process alive as root')
}

process.chdir(__dirname)

const crypto       = require('crypto')
const debug        = require('debug')('nodePush')
const escapeRegExp = require('escape-string-regexp')
const express      = require('express')
const fs           = require('fs')
const net          = require('net')
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
	[ signature, payload ] = String(data).split(/-/)

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

function sendMessage(name, userIDs, payload) {
	if (!/^[a-zA-Z0-9-_]+\.[a-zA-Z0-9-_]+(\.[a-zA-Z0-9-_]+)+$/.test(name)) return false

	debug(`${name} -> ${userIDs.join(',')}`)

	if (config.enableStats) {
		stats.messages[name] = (stats.messages[name] || 0) + 1
	}

	if (userIDs.length) {
		userIDs.forEach(function (userID) {
			io.to(`user-${userID}`).emit(name, payload)
		})
	}
	else {
		io.to('authenticated').emit(name, payload)
	}

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
	io = require('socket.io')(server)

	io.on('connection', function (socket) {
		const id = ++stats.outbound.total
		stats.outbound.current++

		debug(`Client ${id} connected`)

		socket.on('disconnect', function () {
			debug(`Client ${id} disconnected`)

			stats.outbound.current--
		})

		socket.on('userID', function (userID) {
			debug(`Client ${id} sent userID ${userID}`)

			if (!(payload = checkSignature(userID, config.signerKey))) {
				socket.disconnect()
				return
			}

			socket.join('authenticated')
			socket.join(`user-${payload}`)
			socket.emit('authenticated')
		})
	})

	const r = redis.createClient(config.redis)

	r.on('message', function (channel, _message) {
		stats.inbound++
		if (channel === `${config.uuid}:nodePush`) {
			try {
				_message = JSON.parse(_message)
			}
			catch (e) {
				debug(`Error parsing JSON: ${e}`)
				return
			}

			if (!_message.message) return
			if (!_message.userIDs) return

			const message = _message.message
			const userIDs = _message.userIDs.map((item) => parseInt(item, 10))
			const payload = _message.payload

			sendMessage(message, userIDs, payload)
		}
	})

	r.subscribe(`${config.uuid}:nodePush`)
})
