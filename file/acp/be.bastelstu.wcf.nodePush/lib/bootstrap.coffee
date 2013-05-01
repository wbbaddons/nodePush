"@author	Tim Düsterhus"
"@copyright	2012-2013 Tim Düsterhus"
"@license	BSD 3-Clause License <http://opensource.org/licenses/BSD-3-Clause>"
"@package	be.bastelstu.wcf.nodePush"
	
fs = require 'fs'

pusher = null
process.argv.shift()

start = ->
	if pusher?
		pusher.removeAllListeners 'exit'
		pusher.kill 'SIGTERM'
	
	process.argv[0] = process.argv[0].replace('bootstrap.js', 'server.js')
	pusher = require('child_process').spawn 'node', process.argv,
		stdio: 'inherit'
		
	pusher.on 'exit', (code, signal) ->
		if code is 2
			start() 
		else
			process.exit code
		
# Restart on SIGHUP
process.on 'SIGHUP', ->
	console.log 'Got SIGHUP. Restarting'
	start()
	
process.on 'SIGINT', ->
	process.exit 0
process.on 'SIGTERM', ->
	process.exit 0

process.on 'exit', ->
	pusher.kill 'SIGTERM' if pusher?
	
fs.open "#{__dirname}/../tmp/nodePush.master.pid", "w", 0o600, (err, fd) ->
	fs.writeSync fd, process.pid

console.log "Bootstrapping nodePush (pid:#{process.pid})"

start()