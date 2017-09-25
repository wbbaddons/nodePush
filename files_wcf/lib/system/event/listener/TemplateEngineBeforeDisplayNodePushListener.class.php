<?php
/*
 * Copyright (c) 2012 - 2017, Tim Düsterhus
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

namespace wcf\system\event\listener;

use \wcf\system\WCF;

/**
 * Signs the user id.
 */
class TemplateEngineBeforeDisplayNodePushListener implements \wcf\system\event\IEventListener {
	/**
	 * @see	\wcf\system\event\IEventListener::execute()
	 */
	public function execute($eventObj, $className, $eventName) {
		if (!\wcf\system\nodePush\NodePushHandler::getInstance()->isEnabled()) return;
		
		$channels = \wcf\system\push\PushHandler::getInstance()->getChannels();
		
		$payload = [
			'userID'    => WCF::getUser()->userID,
			'timestamp' => TIME_NOW,
			'channels'  => $channels,
			'groups'    => WCF::getUser()->getGroupIDs()
		];
		
		WCF::getTPL()->assign([
			'nodePushSignedUserID' => \wcf\util\CryptoUtil::createSignedString(\wcf\util\JSON::encode($payload))
		]);
	}
}
