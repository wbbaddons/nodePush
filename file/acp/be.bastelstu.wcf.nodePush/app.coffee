### Copyright Information
# @author	Tim Düsterhus
# @copyright	2012-2015 Tim Düsterhus
# @license	BSD 3-Clause License <http://opensource.org/licenses/BSD-3-Clause>
# @package	be.bastelstu.wcf.nodePush
###

panic = -> throw new Error "Cowardly refusing to keep the process alive as root"
panic() if process.getuid?() is 0 or process.getgid?() is 0

winston = require 'winston'
debug = (require 'debug')('nodePush')
express = require 'express'
net = require 'net'
fs = require 'fs'
crypto = require 'crypto'
io = null

console.log "nodePush (pid:#{process.pid})"
console.log "================" + Array(String(process.pid).length).join "="

process.title = "nodePush"

config = require('rc') 'nodePush',
	enableStats: no
	outbound:
		port: 9001
		host: '0.0.0.0'
	inbound:
		port: 9002
		host: '127.0.0.1'
	signerKey: null

unless config.signerKey?
	options_inc_php = fs.readFileSync "#{__dirname}/../../options.inc.php"
	unless matches = /define\('SIGNER_SECRET', '(.*)'\);/.exec options_inc_php
		throw new Error "Cannot find signer secret"
	
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

debug "Inbound-Socket: #{config.inbound.host}:#{config.inbound.port}"
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

# initialize the inbound (where we will receive the messages) socket
initInbound = (callback) ->
	debug 'Initializing inbound socket'
	
	socket = net.createServer (c) ->
		stats.inbound++ if config.enableStats
		
		c.on 'data', (data) ->
			[ message, userIDs ] = data.toString().trim().split /:/
			if userIDs? and userIDs.length
				userIDs = userIDs.split /,/
				userIDs = (parseInt userID for userID in userIDs when not isNaN parseInt userID)
			else
				userIDs = [ ]
			
			setTimeout ->
				sendMessage message, userIDs
			, 20
			
			do c.end
			
		c.on 'end', -> do c.end
		c.setTimeout 5e3, -> do c.end
	socket.on 'error', (e) ->
		throw new Error "Failed when initializing inbound socket: #{e.message}"
	
	socket.listen config.inbound.port, config.inbound.host, null, callback

debug 'Initializing outbound socket'

app = do express
app.use do (require 'cors')
server = (require 'http').Server app
server.on 'error', (e) ->
	throw new Error "Failed when starting http service: #{e.message}"

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

# and finally start up everything
initInbound ->
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
		
		winston.info "Done"
