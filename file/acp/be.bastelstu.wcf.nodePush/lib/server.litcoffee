nodePush Pushserver
===================

Copyright Information
---------------------

	"@author	Tim Düsterhus"
	"@copyright	2012-2013 Tim Düsterhus"
	"@license	BSD 3-Clause License <http://opensource.org/licenses/BSD-3-Clause>"
	"@package	be.bastelstu.wcf.nodePush"

Setup
-----

Load required namespaces.

	express = require 'express'
	http = require 'http'
	io = require 'socket.io'
	net = require 'net'
	fs = require 'fs'

Load config

	try
		config = require '../config.js'
	catch e
		config = { }

Initialize sane values.

	config.outbound ?= { }
	config.outbound.useTCP ?= true
	config.outbound.port ?= 9001
	config.outbound.host ?= '0.0.0.0'
	config.outbound.socket ?= __dirname + "/../outbound.sock"
	config.inbound ?= { }
	config.inbound.useTCP ?= false
	config.inbound.port ?= 9002
	config.inbound.host ?= '127.0.0.1'
	config.inbound.socket ?= __dirname + "/../inbound.sock"
	config.user ?= 'nobody'
	config.group ?= 'nogroup'

Prepare environment

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

Instance of express.

		app: null

Instance of http

		server: null

Instance of socket.io

		io: null

Statistics for the status page.

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

		constructor: ->
			log "nodePush running (pid:#{process.pid})"
			
			if config.inbound.useTCP
				log "Inbound: #{config.inbound.host}:#{config.inbound.port}"
			else
				log "Inbound: #{config.inbound.socket}"
			if config.outbound.useTCP
				log "Outbound: #{config.outbound.host}:#{config.outbound.port}"
			else
				log "Outbound: #{config.outbound.socket}"
			
			
			@stats.bootTime = new Date()
			
			@initUnixSocket()
			@initServer()
			
Bind shutdown function to needed events.

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

Set nice title for PS.

			process.title = 'nodePush'

**initServer()**  
Initialize socket server.

		initServer: ->
			log 'Initializing outbound socket'

Start HTTP service.

			@app = express()
			@server = http.createServer @app
			@io = io.listen @server
			
			listenCallback = =>

Shed root privilegies.

				if process.getuid? and (process.getuid() is 0 or process.getgid() is 0)
					try
						log 'Trying to shed root privilegies'
						process.setgid config.group
						process.setuid config.user
						log "New User ID: #{process.getuid()}, New Group ID: #{process.getgid()}"
					catch e
						log 'Cowardly refusing to keep the process alive as root.'
						process.exit 1

Initialize intervals for tick events. The ticks are sent every 15 / 30 / 60 / 90 / 120 seconds.

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
			
			if config.outbound.useTCP
				@server.listen config.outbound.port, config.outbound.host, null, listenCallback
			else
				@server.listen config.outbound.socket, listenCallback
				fs.chmod config.outbound.socket, '777'

Initialize production environment.

			@io.set 'log level', 1
			@io.set 'browser client etag', true
			@io.set 'browser client minification', true
			@io.set 'browser client gzip', true

Development configuration.

			@io.configure 'development', =>
				@io.set 'log level', 3
				@io.set 'browser client etag', false
				@io.set 'browser client minification', false

Record statistics for Websocket connections.

			@io.sockets.on 'connection', (socket) =>
				@stats.outbound.total++
				@stats.outbound.current++
				
				socket.on 'disconnect', =>
					@stats.outbound.current--

Show the status page when '/' is requested.

			@app.get '/', (req, res) =>
				res.charset = 'utf-8';
				res.type 'txt'
				
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
				
				res.send reply

**sendMessage(name)**  
Sends a message with the given name.

		sendMessage: (name) ->
			return unless /^[a-zA-Z0-9-_]+\.[a-zA-Z0-9-_]+(\.[a-zA-Z0-9-_]+)+$/.test name
			
			@stats.messages[name] ?= 0
			@stats.messages[name]++
			@io.sockets.send name

**initUnixSocket()**  
Initialize PHP side unix socket.

		initUnixSocket: ->
			log 'Initializing inbound socket'
			socket = net.createServer (c) =>
				@stats.inbound++

Pass data to the browsers and close connection.

				c.on 'data', (data) =>
					setTimeout =>
						@sendMessage data.toString().trim()
					, 20
					c.end()
				
				c.on 'end', ->
					c.end()

Kill connection after 5 seconds.

				c.setTimeout 5e3, ->
					c.end()
			
			if config.inbound.useTCP
				socket.listen config.inbound.port, config.inbound.host
			else
				socket.listen config.inbound.socket
				fs.chmod config.inbound.socket, '777'

**shutdown()**  
Performs a clean shutdown of nodePush.

		shutdown: (message = null, code = 0) ->
			if message?
				log "Shutting down: #{message}"
			else
				log 'Shutting down'
			
			fs.unlinkSync config.inbound.socket if not config.inbound.useTCP and fs.existsSync config.inbound.socket
			fs.unlinkSync config.outbound.socket if not config.outbound.useTCP and fs.existsSync config.outbound.socket
			
			
			process.removeAllListeners()
			process.exit code

And finally start the service.

	new be.bastelstu.wcf.nodePush()