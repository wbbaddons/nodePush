<?php

use wcf\system\nodePush\NodePushHandler;
use wcf\system\WCF;

return static function (): void {
	WCF::getTPL()->assign(
		'nodePushHandler',
		NodePushHandler::getInstance(),
	);
};
