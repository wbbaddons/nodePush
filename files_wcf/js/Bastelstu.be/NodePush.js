/*
 * Copyright (c) 2012 - 2016, Tim Düsterhus
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

define([ 'Bastelstu.be/core' ], function (core) {
	"use strict";
	
	const io = new core.Promise(function (resolve, reject) {
		require([ 'socket.io' ], resolve, reject)
	})

	const promise = core.Symbol('promise')
	const resolve = core.Symbol('resolve')
	const reject = core.Symbol('reject')
	const initialized = core.Symbol('initialized')
	
	class NodePush {
		constructor() {
			this[initialized] = false
			this[promise] = new core.Promise((function (_resolve, _reject) {
				this[resolve] = _resolve
				this[reject] = _reject
			}).bind(this))
		}

		/**
		 * Connect to the given host and provide the given signed authentication string.
		 */
		init(host, connectData) {
			if (this[initialized]) return
			this[initialized] = true

			io.then((function (io) {
				const socket = io(host)
				let token = undefined

				socket.on('connect', function () {
					if (token === undefined) {
						socket.emit('connectData', connectData)
					}
					else {
						socket.emit('token', token)
					}
				})

				socket.on('rekey', function (_token) {
					token = _token
				})
				
				socket.on('authenticated', (function () {
					this.connected = true
				}).bind(this))

				socket.on('disconnect', (function () {
					this.connected = false
				}).bind(this))

				this[resolve](socket)
			}).bind(this))
			.catch((function (err) {
				console.log('Initializing nodePush failed:', err)

				this[reject](err)
			}).bind(this))
		}
		
		getFeatureFlags() {
			return [ 'authentication', 'target:channels', 'target:groups', 'target:users', 'target:registered', 'target:guest' ]
		}

		/**
		 * Execute the given callback after connecting to the nodePush service.
		 */
		onConnect(callback) {
			return this[promise]
			.then((function (socket) {
				socket.on('authenticated', function () {
					callback()
				})

				if (this.connected) {
					setTimeout(function () {
						callback()
					}, 0)
				}
			}).bind(this))
		}

		/**
		 * Execute the given callback after disconnecting from the nodePush service.
		 */
		onDisconnect(callback) {
			return this[promise]
			.then(function (socket) {
				socket.on('disconnect', function () {
					callback()
				})
			})
		}

		/**
		 * Execute the given callback after receiving the given message from the nodePush service.
		 */
		onMessage(message, callback) {
			if (!/^[a-zA-Z0-9-_]+\.[a-zA-Z0-9-_]+(\.[a-zA-Z0-9-_]+)+$/.test(message)) {
				return core.Promise.reject(new Error('Invalid message identifier'))
			}

			return this[promise]
			.then(function (socket) {
				socket.on(message, function (payload) {
					callback(payload)
				})
			})
		}
	}

	return new NodePush()
});
