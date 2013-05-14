nodePush Pushserver
===================

	### Copyright Information
	# @author	Tim Düsterhus
	# @copyright	2012-2013 Tim Düsterhus
	# @license	BSD 3-Clause License <http://opensource.org/licenses/BSD-3-Clause>
	# @package	be.bastelstu.wcf.nodePush
	###

Setup
-----

First we import the required packages and make them available in a global variable.

	express = require 'express'
	http = require 'http'
	io = require 'socket.io'
	net = require 'net'
	fs = require 'fs'

Next we try to load the configuration file "config.js".

	try
		filename = "#{__dirname}/../config.js"
		if process.argv[2]
			if process.argv[2].substring(0, 1) is '/'
				filename = process.argv[2]
			else
				filename = "#{__dirname}/../#{process.argv[2]}"
		
		filename = fs.realpathSync filename
		
		console.log "Using config '#{filename}'"
		config = require filename
	catch e
		console.warn e.message
		config = { }

In case not every configuration property is set we initialize it with a default property.

	config.outbound ?= { }
	config.outbound.useTCP ?= true
	config.outbound.port ?= 9001
	config.outbound.host ?= '0.0.0.0'
	config.outbound.socket ?= "#{__dirname}/../tmp/outbound.sock"
	config.inbound ?= { }
	config.inbound.useTCP ?= false
	config.inbound.port ?= 9002
	config.inbound.host ?= '127.0.0.1'
	config.inbound.socket ?= "#{__dirname}/../tmp/inbound.sock"
	config.user ?= 'nobody'
	config.group ?= 'nogroup'

We continue with creating some helper functions.

	log = (message) ->
		console.log "[be.bastelstu.wcf.nodePush] #{message}"
	
	thousandsSeparator = (number) ->
		String(number).replace /(^-?\d{1,3}|\d{3})(?=(?:\d{3})+(?:$|\.))/g, '$1,'
	
	fs.open "#{__dirname}/../tmp/nodePush.child.pid", "w", 0o600, (err, fd) ->
		fs.writeSync fd, process.pid
	
	# Ensure our namespace is present
	be = be ? {}
	be.bastelstu ?= {}
	be.bastelstu.wcf ?= {}

be.bastelstu.wcf.nodePush
=========================

	class be.bastelstu.wcf.nodePush
	
Attributes
----------

`app` will become an instance of `express`.

		app: null

`server` willbecome an instance of `http`.

		server: null

`io` will become an instance of `socket.io`.

		io: null

`stats` is an object with the different statistics recorded. Statistics will be shown on the status page.

		stats:
			status: 0
			outbound: 
				total: 0
				current: 0
			inbound: 0
			messages: { }
			bootTime: new Date()

Methods
-------
**constructor()**  
The constructor is executed when the class is initialized. It prints some helpful information,
such as the PID and the used sockets and continues with initializing everything.

		constructor: ->
			log "nodePush running (pid:#{process.pid})"

First we display the used inbound and outbound sockets.

			if config.inbound.useTCP
				log "Inbound: #{config.inbound.host}:#{config.inbound.port}"
			else
				log "Inbound: #{config.inbound.socket}"
			if config.outbound.useTCP
				log "Outbound: #{config.outbound.host}:#{config.outbound.port}"
			else
				log "Outbound: #{config.outbound.socket}"
			
			
			@stats.bootTime = new Date()

Afterwards we initialize the inbound and outbound connection.

			@initInbound()
			@initOutbound()

In order to do a proper cleanup on shutdown we bind the `shutdown` method to the needed events and signals.

			process.on 'exit', =>
				@shutdown()
			process.on 'uncaughtException', (message) =>
				@shutdown message, 1
			process.on 'SIGINT', =>
				@shutdown()
			process.on 'SIGTERM', =>
				@shutdown()
			process.on 'SIGHUP', =>
				@shutdown null, 2

At the end we set a nice title for `ps`.

			process.title = 'nodePush'

**initOutbound()**  
`initOutbound` initializes the connection to the browser. That includes starting the HTTP server and preparing
socket.io.

		initOutbound: ->
			log 'Initializing outbound socket'

First we start the express based HTTP server.

			@app = express()
			@server = http.createServer @app
			@io = io.listen @server

Afterwards we set socket.io configuration for the default environment. Files will be minified and logging reduced to a minimum.

			@io.set 'log level', 1
			@io.set 'browser client etag', true
			@io.set 'browser client minification', true
			@io.set 'browser client gzip', true

In case `env` is set to development we show some more debug output.

			@io.configure 'development', =>
				@io.set 'log level', 3
				@io.set 'browser client etag', false
				@io.set 'browser client minification', false

Next we listen on the socket.io `connection` event to record statistics.

			@io.sockets.on 'connection', (socket) =>
				@stats.outbound.total++ if @app.get('env') is 'development'
				@stats.outbound.current++
				
				socket.on 'userID', (userID) =>
					socket.get 'userID', (_, currentUserID) =>

In case a client misbehaves, by sending the `userID` twice, we `disconnect` it.

						if currentUserID?
							socket.disconnect()
							return

Mark user as *authenticated* by joining **user**. If a client does not send a `userID` it will not receive any messages.

						socket.set 'userID', userID
						socket.join 'authenticated'
						socket.join "user#{userID}"
						socket.emit 'authenticated'
				
				socket.on 'disconnect', =>
					@stats.outbound.current--
							
We continue with creating a callback for the `listen` call.

			listenCallback = =>

In case we are running as root we try to shed root privilegies. If this is not possible we exit, as a service
running as root is dangerous.

				if process.getuid? and (process.getuid() is 0 or process.getgid() is 0)
					try
						log 'Trying to shed root privilegies'
						process.setgid config.group
						process.setuid config.user
						log "New User ID: #{process.getuid()}, New Group ID: #{process.getgid()}"
					catch e
						log 'Cowardly refusing to keep the process alive as root.'
						process.exit 1

After the the HTTP server is listening and we are no longer running as root we start some intervals for the builtin tick events.

				setInterval =>
					@sendMessage 'be.bastelstu.wcf.nodePush.tick15'
				, 15e3
				setInterval =>
					@sendMessage 'be.bastelstu.wcf.nodePush.tick30'
				, 30e3
				setInterval =>
					@sendMessage 'be.bastelstu.wcf.nodePush.tick60'
				, 60e3
				setInterval =>
					@sendMessage 'be.bastelstu.wcf.nodePush.tick90'
				, 90e3
				setInterval =>
					@sendMessage 'be.bastelstu.wcf.nodePush.tick120'
				, 120e3
				
				log "Done"

Start listening on the configured outbound socket.

			if config.outbound.useTCP
				@server.listen config.outbound.port, config.outbound.host, null, listenCallback
			else
				@server.listen config.outbound.socket, listenCallback
				fs.chmod config.outbound.socket, '777'

Show the status page when '/' is requested.

			@app.get '/', (req, res) =>
				res.charset = 'utf-8';
				res.type 'txt'

Show detailed information when environment is `development`.

				if @app.get('env') is 'development'
					@stats.status++
					reply = """
					Up since: #{@stats.bootTime}
					Status page: #{thousandsSeparator @stats.status} Requests
					Outbound: #{thousandsSeparator @stats.outbound.current} now - #{thousandsSeparator @stats.outbound.total} Total
					Inbound: #{thousandsSeparator @stats.inbound}
					Messages:
					"""
					for message, amount of @stats.messages
						reply += "\n	#{message}: #{thousandsSeparator amount}"
				else
					reply = """
					Up since: #{@stats.bootTime}
					Outbound: #{thousandsSeparator @stats.outbound.current} now
					"""
				
				res.send reply

**sendMessage(name)**  
Sends a message with the given name.

		sendMessage: (name, userIDs = [ ]) ->
			return unless /^[a-zA-Z0-9-_]+\.[a-zA-Z0-9-_]+(\.[a-zA-Z0-9-_]+)+$/.test name
			
			if name is 'be.bastelstu.wcf.nodePush._restart'
				process.kill process.pid, 'SIGHUP'
			
			if @app.get('env') is 'development'
				@stats.messages[name] ?= 0
				@stats.messages[name]++
			
			if userIDs.length
				@io.sockets.in("user#{userID}").send name for userID in userIDs
			else
				@io.sockets.in('authenticated').send name

**initInbound()**  
`initInbound` initializes the PHP side socket.

		initInbound: ->
			log 'Initializing inbound socket'

We start by creating a server.

			socket = net.createServer (c) =>
				@stats.inbound++ if @app.get('env') is 'development'

In case data is written to the server we pass it to the connected browsers and close the connection afterwards.

				c.on 'data', (data) =>
					[ message, userIDs ] = data.toString().trim().split /:/
					if userIDs? and userIDs.length
						userIDs = userIDs.split /,/
						userIDs = (parseInt userID for userID in userIDs when not isNaN parseInt userID)
					else
						userIDs = [ ]
					
					setTimeout =>
						@sendMessage message, userIDs
					, 20
					c.end()
				
				c.on 'end', ->
					c.end()

In case nothing happens within 5 seconds we close the connection in order to save resources.

				c.setTimeout 5e3, ->
					c.end()

After all callbacks are bound we start listening.

			if config.inbound.useTCP
				socket.listen config.inbound.port, config.inbound.host
			else
				socket.listen config.inbound.socket
				fs.chmod config.inbound.socket, '777'

**shutdown()**  
`shutdown` performs a clean shutdown of nodePush. It cleans up the unix socket files.

		shutdown: (message = null, code = 0) ->
			if message?
				log "Shutting down: #{message}"
			else
				log 'Shutting down'
			
			fs.unlinkSync config.inbound.socket if not config.inbound.useTCP and fs.existsSync config.inbound.socket
			fs.unlinkSync config.outbound.socket if not config.outbound.useTCP and fs.existsSync config.outbound.socket
			
			
			process.removeAllListeners()
			process.exit code

In the end we finally initialize the class with starts all the services.

	new be.bastelstu.wcf.nodePush()
