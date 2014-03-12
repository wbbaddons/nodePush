nodePush - Frontend
===================

This is the frontend JavaScript for [**nodePush**](https://github.com/wbbaddons/nodePush). It transparently handles
everything that has to be done in order to connect to **nodePush** and provides a nice API for 3rd party developers.

	### Copyright Information
	# @author	Tim Düsterhus
	# @copyright	2012-2013 Tim Düsterhus
	# @license	BSD 3-Clause License <http://opensource.org/licenses/BSD-3-Clause>
	# @package	be.bastelstu.wcf.nodePush
	###

## Code
We start by setting up our environment by ensuring some sane values for both `$` and `window`,
enabling EMCAScript 5 strict mode and overwriting console to prepend the name of the class.

	(($, window) ->
		"use strict";
		
		console =
			log: (message) ->
				window.console.log "[be.bastelstu.wcf.nodePush] #{message}" unless production?
			warn: (message) ->
				window.console.warn "[be.bastelstu.wcf.nodePush] #{message}" unless production?
			error: (message) ->
				window.console.error "[be.bastelstu.wcf.nodePush] #{message}" unless production?

Continue with defining the needed variables. All variables are local to our closure and will be
exposed by a function if necessary.

		socket = null
		connected = false
		initialized = false
		events =
			connect: $.Callbacks()
			disconnect: $.Callbacks()
			message: { }

Initialize socket.io to enable nodePush.

		init = (host) ->
			return if initialized
			initialized = true
			console.log 'Initializing nodePush'
			
			unless window.io?
				console.error 'nodePush not available, aborting'
				return
				
			socket = window.io.connect host
			
			socket.on 'connect', ->
				console.log 'Connected to nodePush'
				socket.emit 'userID', WCF.User.userID
			
			socket.on 'authenticated', ->
				console.log 'Exchanged userID with nodePush'
				connected = true
				do events.connect.fire
			
			socket.on 'disconnect', ->
				connected = false
				console.warn 'Lost connection to nodePush'
				do events.disconnect.fire
			
			socket.on 'message', (message) ->
				return unless events.message[message]?
				
				do events.message[message].fire

Add a new `callback` that will be called when a connection to nodePush is established and the
userID was exchanged. The given `callback` will be called once if a connection is established at
time of calling. Return `true` on success and `false` otherwise.

		onConnect = (callback) ->
			return false unless $.isFunction callback
			
			events.connect.add callback
			
			if connected
				setTimeout ->
					do callback
				, 0
			true

Add a new `callback` that will be called when the connection to nodePush is lost. Return `true`
on success and `false` otherwise.

		onDisconnect = (callback) ->
			return false unless $.isFunction callback
			
			events.disconnect.add callback
			true

Add a new `callback` that will be called when the specified `message` is received. Return `true`
on success and `false` otherwise.

		onMessage = (message, callback) ->
			return false unless $.isFunction callback
			return false unless /^[a-zA-Z0-9-_]+\.[a-zA-Z0-9-_]+(\.[a-zA-Z0-9-_]+)+$/.test message
			
			events.message[message] ?= $.Callbacks()
			events.message[message].add callback
			true

And finally export the public methods and variables.

		window.be ?= {}
		be.bastelstu ?= {}
		be.bastelstu.wcf ?= {}
		be.bastelstu.wcf.nodePush = 
			init: init
			onConnect: onConnect
			onDisconnect: onDisconnect
			onMessage: onMessage

	)(jQuery, @)
