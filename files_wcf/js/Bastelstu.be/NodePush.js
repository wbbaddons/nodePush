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
	
	let io = undefined
	
	function getIo() {
		if (io !== undefined) return core.Promise.resolve(io)

		return new core.Promise(function (resolve, reject) {
			require([ 'socket.io' ], function (_io) {
				io = _io

				resolve(io)
			}, reject)
		})
	}

	const promise = core.Symbol('promise')

	class NodePush {
		constructor() {
			this[promise] = undefined
		}

		init(host, signedUserID) {
			if (this[promise] !== undefined) return

			this[promise] =
			getIo()
			.then((function (io) {
				const socket = io(host)
				socket.on('connect', socket.emit.bind(socket, 'userID', signedUserID))

				socket.on('authenticated', (function () {
					this.connected = true
				}).bind(this))

				socket.on('disconnect', (function () {
					this.connected = false
				}).bind(this))

				return socket
			}).bind(this))
			.catch((function (err) {
				console.log('Initializing nodePush failed:', err)

				return core.Promise.reject(err)
			}).bind(this))
		}

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

		onDisconnect(callback) {
			return this[promise]
			.then(function (socket) {
				socket.on('disconnect', function () {
					callback()
				})
			})
		}

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
