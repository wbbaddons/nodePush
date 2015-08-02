<?php
namespace wcf\system\nodePush;
use wcf\util\StringUtil;

/**
 * DO NOT USE NodePushHandler DIRECTLY. USE:
 * \wcf\system\push\PushHandler
 * It uses the same API.
 *
 * @author	Tim Düsterhus
 * @copyright	2012-2015 Tim Düsterhus
 * @license	BSD 3-Clause License <http://opensource.org/licenses/BSD-3-Clause>
 * @package	be.bastelstu.wcf.nodePush
 * @subpackage	system.nodePush
 */
class NodePushHandler extends \wcf\system\SingletonFactory {
	/**
	 * Array of messages to send at shutdown.
	 * 
	 * @var	array<string>
	 */
	private $deferred = array();
	
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
		
		return true;
	}
	
	/**
	 * @see	\wcf\system\push\PushHandler::sendMessage()
	 */
	public function sendMessage($message, array $userIDs = array(), array $payload = array()) {
		if (!$this->isEnabled()) return false;
		if (!\wcf\data\package\Package::isValidPackageName($message)) return false;
		$userIDs = array_unique(\wcf\util\ArrayUtil::toIntegerArray($userIDs));
		
		try {
			$http = new \wcf\util\HTTPRequest(NODEPUSH_HOST.'/deliver', array(
				'timeout' => 2,
				'method' => 'POST'
			), \wcf\util\Signer::createSignedString(
				\wcf\util\JSON::encode(array(
					'message' => $message,
					'userIDs' => $userIDs,
					'payload' => $payload
				))
			));
			
			$http->addHeader('content-type', 'application/octet-stream');
			$http->execute();
			return true;
		}
		catch (\Exception $e) {
			return false;
		}
	}
}
