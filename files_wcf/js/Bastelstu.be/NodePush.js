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

define([ ], function () {
	"use strict";
	
	let io = undefined;

	class NodePush {
		constructor() {
			this.status = 'waiting'
		}

		init(host, signedUserID) {
			if (this.status !== 'waiting') return
			this.status = 'initializing'

			require([ 'socket.io' ], (function (_io) {
				this.status = 'initialized'

				io = _io
				this.socket = io(host)
				this.socket.on('connect', this.socket.emit.bind(this.socket, 'userID', signedUserID))

				this.socket.on('authenticated', (function () {
					this.connected = true
				}).bind(this))

				this.socket.on('disconnect', (function () {
					this.connected = false
				}).bind(this))
			}).bind(this), (function (err) {
				this.status = 'error'
				console.log(err)
			}).bind(this))
		}

		getStatus() {
			return this.status
		}

		onConnect(callback) {
			if (this.status !== 'initialized') throw new Error('Not ready')

			this.socket.on('authenticated', function () {
				callback()
			})

			if (this.connected) {
				setTimeout(function () {
					callback()
				}, 0)
			}
		}

		onDisconnect(callback) {
			if (this.status !== 'initialized') throw new Error('Not ready')

			this.socket.on('disconnect', function () {
				callback()
			})
		}

		onMessage(message, callback) {
			if (this.status !== 'initialized') throw new Error('Not ready')

			if (!/^[a-zA-Z0-9-_]+\.[a-zA-Z0-9-_]+(\.[a-zA-Z0-9-_]+)+$/.test(message)) {
				throw new Error('Invalid message identifier')
			}

			this.socket.on(message, function (payload) {
				callback(payload)
			})
		}
	}

	return new NodePush()
});
