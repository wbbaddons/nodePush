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

namespace wcf\system\nodePush;

use \wcf\system\cache\CacheHandler;

/**
 * Transmits push messages to the nodePush service.
 */
class NodePushHandler extends \wcf\system\SingletonFactory {
	/**
	 * @see	\wcf\system\push\PushHandler::getFeatureFlags()
	 */
	public function getFeatureFlags() {
		return [ 'authentication', 'target:channels', 'target:groups', 'target:users', 'target:registered', 'target:guest' ];
	}

	/**
	 * @see	\wcf\system\push\PushHandler::isEnabled()
	 */
	public function isEnabled() {
		return (boolean) NODEPUSH_HOST;
	}
	
	/**
	 * @see	\wcf\system\push\PushHandler::isRunning()
	 */
	public function isRunning() {
		if (!$this->isEnabled()) return false;
		if (!(CacheHandler::getInstance()->getCacheSource() instanceof \wcf\system\cache\source\RedisCacheSource)) return false;
		
		return true;
	}
	
	/**
	 * @see	\wcf\system\push\PushHandler::sendMessage()
	 */
	public function sendMessage($message, array $userIDs = [ ], array $payload = [ ]) {
		if (!$this->isRunning()) return false;
		if (is_array($message)) {
			if (!isset($message['message'])) return false;
			if (!\wcf\data\package\Package::isValidPackageName($message['message'])) return false;
			
			try {
				$redis = CacheHandler::getInstance()->getCacheSource()->getRedis();
				return $redis->publish('nodePush', \wcf\util\JSON::encode([
					'message' => $message['message'],
					'target'  => isset($message['target']) ? $message['target'] : null,
					'payload' => isset($message['payload']) ? $message['payload'] : [ ],
					
				]));
			}
			catch (\Exception $e) {
				return false;
			}
			
			return;
		}
		
		if (!\wcf\data\package\Package::isValidPackageName($message)) return false;
		$userIDs = array_unique(\wcf\util\ArrayUtil::toIntegerArray($userIDs));
		$target = null;
		if ($userIDs) {
			$target = [ 'users' => array_values($userIDs) ];
		}
		return $this->sendMessage([
			'message' => $message,
			'payload' => $payload,
			'target' => $target
		]);
	}
}
