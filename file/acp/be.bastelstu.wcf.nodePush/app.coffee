### Copyright Information
# @author	Tim Düsterhus
# @copyright	2012-2013 Tim Düsterhus
# @license	BSD 3-Clause License <http://opensource.org/licenses/BSD-3-Clause>
# @package	be.bastelstu.wcf.nodePush
###

debug = (require 'debug')('nodePush')
express = require 'express'
net = require 'net'
fs = require 'fs'
chroot = require 'chroot'
io = null

logger = new (require 'caterpillar').Logger
	level: 6

((logger.pipe new (require('caterpillar-filter').Filter)).pipe new (require('caterpillar-human').Human)).pipe process.stdout

console.log "nodePush (pid:#{process.pid})"
console.log "================" + Array(String(process.pid).length).join "="

process.title = "nodePush"

# Try to load config
try
	filename = "#{__dirname}/config"
	
	# configuration file was passed via `process.argv`
	filename = (require 'path').resolve process.argv[2] if process.argv[2]?
	
	filename = fs.realpathSync filename
	
	logger.log "info", "Using config '#{filename}'"
	config = require filename
catch e
	logger.log "warn", """Cannot load config: #{e}"""
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
config.user ?= 'nobody'
config.group ?= 'nogroup'

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
	logger.log "info", "Inbound-Socket: #{config.inbound.host}:#{config.inbound.port}"
else
	logger.log "info", "Inbound-Socket: #{config.inbound.socket}"
if config.outbound.useTCP
	logger.log "info", "Outbound-Socket: #{config.outbound.host}:#{config.outbound.port}"
else
	logger.log "info", "Outbound-Socket: #{config.outbound.socket}"

# helper function (see http://stackoverflow.com/a/6502556/782822)
thousandsSeparator = (number) -> String(number).replace /(^-?\d{1,3}|\d{3})(?=(?:\d{3})+(?:$|\.))/g, '$1,'

# sends the given message to the given userIDs
sendMessage = (name, userIDs = [ ]) ->
	return false unless /^[a-zA-Z0-9-_]+\.[a-zA-Z0-9-_]+(\.[a-zA-Z0-9-_]+)+$/.test name
	
	debug "#{name} -> #{userIDs.join ','}"
	
	if debug.enabled
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
		stats.inbound++ if debug.enabled
		
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
		logger.log "emerg", 'Failed when initializing inbound socket', e
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
	do (signal) -> process.once signal, ->
		logger.log "info", "Received:", signal
		do cleanup
		do process.exit

debug 'Initializing outbound socket'

app = do express
app.use do (require 'cors')
server = (require 'http').Server app
server.on 'error', (e) ->
	logger.log "emerg", 'Failed when starting http: ', e
	process.exit 1

# show status page
app.get '/', (req, res) ->
	debug "Status page hit"
	
	res.charset = 'utf-8';
	res.type 'txt'
	
	if debug.enabled
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
		# check whether we have to drop privileges
		if process.getuid? and (process.getuid() is 0 or process.getgid() is 0)
			logger.log "info", 'Trying to switch user to', config.user, 'and group', config.group
			try
				chroot '/', config.user, config.group
				logger.log "notice", "New User ID: #{process.getuid()}, New Group ID: #{process.getgid()}"
			catch e
				console.log e
				logger.log "emerg", e, 'Cowardly refusing to keep the process alive as root.'
				process.exit 1
				
		# initialize socket.io
		io = (require 'socket.io')(server)
		
		# handle connections to the websocket
		io.on 'connection', (socket) ->
			debug "Client connected"
			stats.outbound.total++ if debug.enabled
			stats.outbound.current++
			
			socket.on 'disconnect', ->
				debug "Client disconnected"
				stats.outbound.current--
			
			socket.on 'userID', (userID) ->
				debug "Client sent userID: #{userID}"
				socket.join 'authenticated'
				socket.join "user-#{userID}"
				socket.emit 'authenticated'
		
		# initialize ticks
		for intervalLength in [ 15, 30, 60, 90, 120 ]
			do (intervalLength) ->
				setInterval (-> sendMessage "be.bastelstu.wcf.nodePush.tick#{intervalLength}"), intervalLength * 1e3
		
		# everything ready
		logger.log "info", "Done"

	if config.outbound.useTCP
		server.listen config.outbound.port, config.outbound.host, null, callback
	else
		server.listen config.outbound.socket, callback
		fs.chmod config.outbound.socket, '777'
