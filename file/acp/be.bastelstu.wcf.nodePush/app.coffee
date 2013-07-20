### Copyright Information
# @author	Tim Düsterhus
# @copyright	2012-2013 Tim Düsterhus
# @license	BSD 3-Clause License <http://opensource.org/licenses/BSD-3-Clause>
# @package	be.bastelstu.wcf.nodePush
###

express = require 'express'
http = require 'http'
net = require 'net'
fs = require 'fs'
path = require 'path'
posix = require 'posix'
io = null

logger = new (require 'caterpillar').Logger
	level: 6

((logger.pipe new (require('caterpillar-filter').Filter)).pipe new (require('caterpillar-human').Human)).pipe process.stdout

console.log "nodePush (pid:#{process.pid})"
console.log "================" + Array(String(process.pid).length).join "="

process.title = "nodePush"

# Try to load config
try
	filename = "#{__dirname}/config.js"

	# configuration file was passed via `process.argv`
	if process.argv[2]
		if process.argv[2].substring(0, 1) is '/'
			filename = process.argv[2]
		else
			filename = "#{__dirname}/#{process.argv[2]}"
	
	filename = fs.realpathSync filename
	
	logger.log "info", "Using config '#{filename}'"
	config = require filename
catch e
	logger.log "warn", e.message
	config = { }

# default values for configuration
config.outbound ?= { }
config.outbound.useTCP ?= true
config.outbound.port ?= 9001
config.outbound.host ?= '0.0.0.0'
config.outbound.socket ?= "#{__dirname}/tmp/outbound.sock"
config.inbound ?= { }
config.inbound.useTCP ?= false
config.inbound.port ?= 9002
config.inbound.host ?= '127.0.0.1'
config.inbound.socket ?= "#{__dirname}/tmp/inbound.sock"
config.disableAutorestart = no
config.user ?= 'nobody'
config.group ?= 'nogroup'
config.chroot ?= __dirname

# initialize statistics
stats =
	status: 0
	outbound: 
		total: 0
		current: 0
	inbound: 0
	messages: { }
	bootTime: new Date()

if config.inbound.useTCP
	logger.log "info", "Inbound: #{config.inbound.host}:#{config.inbound.port}"
else
	logger.log "info", "Inbound: #{config.inbound.socket}"
if config.outbound.useTCP
	logger.log "info", "Outbound: #{config.outbound.host}:#{config.outbound.port}"
else
	logger.log "info", "Outbound: #{config.outbound.socket}"

# helper function (see http://stackoverflow.com/a/6502556/782822)
thousandsSeparator = (number) -> String(number).replace /(^-?\d{1,3}|\d{3})(?=(?:\d{3})+(?:$|\.))/g, '$1,'

# sends the given message to the given userIDs
sendMessage = (name, userIDs = [ ]) ->
	return false unless /^[a-zA-Z0-9-_]+\.[a-zA-Z0-9-_]+(\.[a-zA-Z0-9-_]+)+$/.test name
	
	logger.log "debug", "#{name} -> #{userIDs.join ','}"

	if name is 'be.bastelstu.wcf.nodePush._restart' and not config.disableAutorestart
		process.kill process.pid, 'SIGUSR2'
	
	if (app.get 'env') is 'development'
		stats.messages[name] ?= 0
		stats.messages[name]++
	
	if userIDs.length
		(io.sockets.in "user#{userID}").send name for userID in userIDs
	else
		(io.sockets.in 'authenticated').send name

# initialize the inbound (where we will receive the messages) socket
initInbound = (callback) ->
	logger.log "debug", 'Initializing inbound socket'

	socket = net.createServer (c) =>
		stats.inbound++ if (app.get 'env') is 'development'

		c.on 'data', (data) =>
			[ message, userIDs ] = data.toString().trim().split /:/
			if userIDs? and userIDs.length
				userIDs = userIDs.split /,/
				userIDs = (parseInt userID for userID in userIDs when not isNaN parseInt userID)
			else
				userIDs = [ ]
			
			setTimeout =>
				sendMessage message, userIDs
			, 20

			do c.end
			
		c.on 'end', -> do c.end
		c.setTimeout 5e3, -> do c.end
	socket.on 'error', (e) ->
		logger.log "emerg", 'Failed when initializing inbound socket'
		logger.log "emerg", String e
		process.exit 1
	
	if config.inbound.useTCP
		socket.listen config.inbound.port, config.inbound.host, null, callback
	else
		socket.listen config.inbound.socket, callback
		fs.chmod config.inbound.socket, '777'

# try to clean up
cleanup = ->
	logger.log "info", "Cleaning up"

	fs.unlinkSync config.inbound.socket if not config.inbound.useTCP and fs.existsSync config.inbound.socket
	fs.unlinkSync config.outbound.socket if not config.outbound.useTCP and fs.existsSync config.outbound.socket

for signal in [ 'SIGINT', 'SIGTERM', 'SIGHUP' ]
	do (signal) ->
		process.once signal, ->
			do cleanup
			do process.exit

for signal in [ 'SIGUSR2' ]
	do (signal) ->
		process.once signal, ->
			do cleanup
			process.kill process.pid, signal

logger.log "debug", 'Initializing outbound socket'

app = do express
server = http.createServer app
server.on 'error', (e) ->
	logger.log "emerg", 'Failed when initializing inbound socket'
	logger.log "emerg", String e
	process.exit 1

# show status page
app.get '/', (req, res) ->
	logger.log "debug", "Status page hit"

	res.charset = 'utf-8';
	res.type 'txt'

	if (app.get 'env') is 'development'
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
	callback = ->
		if process.getuid? and (process.getuid() is 0 or process.getgid() is 0)
			groupData = posix.getgrnam config.group
			userData = posix.getpwnam config.user

			if config.chroot isnt false
				try
					logger.log "info", 'Trying to chroot'
					process.chdir config.chroot
					posix.chroot config.chroot
					logger.log "notice", "Successfully chrooted to #{config.chroot}"
					unless config.outbound.useTCP
						config.outbound.socket = path.relative config.chroot, config.outbound.socket
						if (config.outbound.socket.indexOf '../') isnt -1
							logger.log "warn", "I won't be able to cleanup the outbound socket"
					unless config.inbound.useTCP
						config.inbound.socket = path.relative config.chroot, config.inbound.socket
						if (config.inbound.socket.indexOf '../') isnt -1
							logger.log "warn", "I won't be able to cleanup the inbound socket"
				catch e
					logger.log "crit", e
					logger.log "crit", 'Failed to chroot'
					process.exit 1
			
			try
				logger.log "info", "Trying to shed root privilegies to #{config.group}:#{config.user}"
				posix.setregid groupData.gid, groupData.gid
				posix.setreuid userData.uid, userData.uid
				throw new Error 'We are not the user we expect us to be' if posix.getuid() isnt userData.uid or posix.getgid() isnt groupData.gid
				logger.log "notice", "New User ID: #{posix.getuid()}, New Group ID: #{posix.getgid()}"
			catch e
				logger.log "emerg", e
				logger.log "emerg", 'Cowardly refusing to keep the process alive as root.'
				process.exit 1
		
		io = require 'socket.io'
		io = io.listen server
		io.set 'log level', 1
		io.set 'browser client etag', true
		io.set 'browser client minification', true
		io.set 'browser client gzip', true if config.chroot is false
		
		if (app.get 'env') is 'development'
			io.set 'log level', 3
			io.set 'browser client etag', false
			io.set 'browser client minification', false
		
		# handle connections to the websocket
		io.sockets.on 'connection', (socket) ->
			logger.log "debug", "Client connected"
			stats.outbound.total++ if (app.get 'env') is 'development'
			stats.outbound.current++
			
			socket.on 'userID', (userID) ->
				logger.log "debug", "Client sent userID"
				socket.get 'userID', (_, currentUserID) ->
					if currentUserID?
						logger.log "notice", "Killing retarded client"
						
						do socket.disconnect
						return
					
					socket.set 'userID', userID
					socket.join 'authenticated'
					socket.join "user#{userID}"
					socket.emit 'authenticated'
					
					socket.on 'disconnect', ->
						logger.log "debug", "Client disconnected"
						stats.outbound.current--
						
		for intervalLength in [ 15, 30, 60, 90, 120 ]
			do (intervalLength) ->
				setInterval ->
					sendMessage "be.bastelstu.wcf.nodePush.tick#{intervalLength}"
				, intervalLength * 1e3
				
		logger.log "info", "Done"

	if config.outbound.useTCP
		server.listen config.outbound.port, config.outbound.host, null, callback
	else
		server.listen config.outbound.socket, callback
		fs.chmod config.outbound.socket, '777'
