# Copyright (C) 2012 - 2015 Tim Düsterhus
# 
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.
# 
# You should have received a copy of the GNU Affero General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

panic = -> throw new Error "Cowardly refusing to keep the process alive as root"
panic() if process.getuid?() is 0 or process.getgid?() is 0

process.chdir __dirname
serverVersion = (require './package.json').version
(require 'child_process').exec 'git describe --always', (err, stdout, stderr) -> serverVersion = stdout.trim() unless err?

debug = (require 'debug')('nodePush')
express = require 'express'
net = require 'net'
fs = require 'fs'
crypto = require 'crypto'
io = null

console.log "nodePush #{serverVersion} (pid:#{process.pid})"

config = require('rc') 'nodePush',
	enableStats: no
	outbound:
		port: 9001
		host: '0.0.0.0'
	signerKey: null

process.title = "nodePush #{config.outbound.host}:#{config.outbound.port}"

unless config.signerKey?
	try
		options_inc_php = fs.readFileSync "#{__dirname}/../../options.inc.php"
		unless matches = /define\('SIGNER_SECRET', '(.*)'\);/.exec options_inc_php
			throw new Error "options.inc.php does not contain the SIGNER_SECRET option."
	catch e
		throw new Error "Cannot find signer secret: #{e}"
	config.signerKey = matches[1].replace("\\'", "'").replace("\\\\", "\\")
	debug "Extracted #{config.signerKey} as Signer key"

# initialize statistics
stats =
	status: 0
	outbound: 
		total: 0
		current: 0
	inbound: 0
	messages: { }
	bootTime: new Date()

debug "Outbound-Socket: #{config.outbound.host}:#{config.outbound.port}"

# helper function (see http://stackoverflow.com/a/6502556/782822)
thousandsSeparator = (number) -> String(number).replace /(^-?\d{1,3}|\d{3})(?=(?:\d{3})+(?:$|\.))/g, '$1,'

checkSignature = (data, key) ->
	[ signature, payload ] = String(data).split /-/
	
	unless payload?
		debug "Invalid signature #{data}"
		return false
		
	payload = new Buffer payload, 'base64'
	if signature.length isnt 40
		debug "Invalid signature #{data}"
		return false
	else
		hmac = crypto.createHmac 'sha1', key
		hmac.update payload
		digest = hmac.digest 'hex'
		
		# https://www.isecpartners.com/blog/2011/february/double-hmac-verification.aspx
		given = crypto.createHmac 'sha1', key
		given.update signature
		
		calculated = crypto.createHmac 'sha1', key
		calculated.update digest
		
		if given.digest('hex') isnt calculated.digest('hex')
			debug "Invalid signature #{data}"
			
			return false
		else
			return payload

# sends the given message to the given userIDs
sendMessage = (name, userIDs = [ ]) ->
	return false unless /^[a-zA-Z0-9-_]+\.[a-zA-Z0-9-_]+(\.[a-zA-Z0-9-_]+)+$/.test name
	
	debug "#{name} -> #{userIDs.join ','}"
	
	if config.enableStats
		stats.messages[name] ?= 0
		stats.messages[name]++
	
	if userIDs.length
		(io.to "user-#{userID}").send name for userID in userIDs
	else
		(io.to 'authenticated').send name
	true
app = do express
app.use do (require 'cors')
app.use do (require 'body-parser').raw
server = (require 'http').Server app
server.on 'error', (e) -> throw new Error "Failed when starting http service: #{e.message}"

# show status page
app.get '/', (req, res) ->
	debug "Status page hit"
	
	res.charset = 'utf-8';
	res.type 'txt'
	
	if config.enableStats
		stats.status++
		reply = """
		Up since: #{stats.bootTime}
		Status page: #{thousandsSeparator stats.status} Requests
		Outbound: #{thousandsSeparator stats.outbound.current} now - #{thousandsSeparator stats.outbound.total} Total
		Inbound: #{thousandsSeparator stats.inbound}
		Messages:
		"""
		for message, amount of stats.messages
			reply += "\n	#{message}: #{thousandsSeparator amount}"
	else
		reply = """
		Up since: #{stats.bootTime}
		Outbound: #{thousandsSeparator stats.outbound.current} now
		"""
	
	res.send reply

app.post '/deliver', (req, res) ->
	stats.inbound++ if config.enableStats
	
	unless payload = checkSignature req.body, config.signerKey
		res.sendStatus 400
		return
	try
		payload = JSON.parse payload
	catch e
		debug "Error parsing JSON: #{e}"
		res.sendStatus 400
		return
	
	unless payload.message?
		res.sendStatus 400
		return
	unless payload.userIDs?
		res.sendStatus 400
		return
		
	message = payload.message
	userIDs = payload.userIDs.map (item) -> parseInt item, 10
	
	if sendMessage message, userIDs
		res.sendStatus 201
	else
		res.sendStatus 400

# and finally start up everything
server.listen config.outbound.port, config.outbound.host, null, ->
	# initialize socket.io
	io = (require 'socket.io')(server)
	
	# handle connections to the websocket
	io.on 'connection', (socket) ->
		debug "Client connected"
		stats.outbound.total++ if config.enableStats
		stats.outbound.current++
		
		socket.on 'disconnect', ->
			debug "Client disconnected"
			stats.outbound.current--
		
		socket.on 'userID', (userID) ->
			debug "Client sent userID: #{userID}"
			
			unless payload = checkSignature userID, config.signerKey
				# nope
				do socket.disconnect
				return
					
			socket.join 'authenticated'
			socket.join "user-#{payload}"
			socket.emit 'authenticated'
	
	# initialize ticks
	for intervalLength in [ 15, 30, 60, 90, 120 ]
		do (intervalLength) ->
			setInterval (-> sendMessage "be.bastelstu.wcf.nodePush.tick#{intervalLength}"), intervalLength * 1e3
	
	console.log "At your service"
