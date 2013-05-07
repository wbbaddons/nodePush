# nodePush

nodePush is an open source push library for [WoltLab Community Framework](http://github.com/WoltLab/WCF). It provides an easy to use API for both, PHP and JavaScript and is based on node.js and socket.io.

## How to use

### On the server
```php
<?php
$pushHandler = \wcf\system\nodePush\NodePushHandler::getInstance();

if ($pushHandler->isRunning()) {
	// second parameter can contain an integer array with userIDs.
	// when leaving it empty, the message will be sent to all connected clients.
	$pushHandler->sendMessage('be.bastelstu.wcf.nodPush.hello', array());
}
?>
```

### On the client
```javascript
be.bastelstu.wcf.nodePush.onMessage('be.bastelstu.wcf.nodPush.hello', function() {
	alert('World!');
});
```

License
-------

For licensing information refer to the LICENSE file in this folder.
