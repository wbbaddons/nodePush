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
		
		try {
			$sock = $this->connect();
			if ($sock === false) return false;
			
			fclose($sock);
		}
		catch (\Exception $e) {
			// gotta catch 'em all
			try {
				if (is_resource($sock)) fclose($sock);
			}
			catch (\Exception $e) { }
			
			return false;
		}
		
		return true;
	}
	
	/**
	 * Connects to the inbound socket. Returns false if the connection failed.
	 * 
	 * @return	boolean|resource
	 */
	private function connect() {
		return stream_socket_client(NODEPUSH_SOCKET, $errno, $errstr, 1);
	}
	
	/**
	 * @see	\wcf\system\push\PushHandler::sendMessage()
	 */
	public function sendMessage($message, $userIDs = array()) {
		if (!$this->isEnabled()) return false;
		if (!\wcf\data\package\Package::isValidPackageName($message)) return false;
		$userIDs = array_unique(\wcf\util\ArrayUtil::toIntegerArray($userIDs));
		
		try {
			$sock = $this->connect();
			if ($sock === false) return false;
			
			$success = fwrite($sock, $message.($userIDs ? ':'.implode(',', $userIDs) : ''));
			fclose($sock);
		}
		catch (\Exception $e) {
			// gotta catch 'em all
			try {
				if (is_resource($sock)) fclose($sock);
			}
			catch (\Exception $e) { }
			
			return false;
		}
		
		return (boolean) $success;
	}
	
	/**
	 * @deprecated Use \wcf\system\push\PushHandler::sendDeferredMessage()
	 */
	public function sendDeferredMessage($message, $userIDs = array()) {
		if (!$this->isEnabled()) return false;
		if (!\wcf\data\package\Package::isValidPackageName($message)) return false;
		$userIDs = array_unique(\wcf\util\ArrayUtil::toIntegerArray($userIDs));
		
		$this->deferred[] = array(
			'message' => $message,
			'userIDs' => $userIDs
		);
		
		return true;
	}
	
	/**
	 * @deprecated See \wcf\system\nodePush\NodePushHandler::sendDeferredMessage()
	 */
	public function __destruct() {
		foreach ($this->deferred as $data) {
			$this->sendMessage($data['message'], $data['userIDs']);
		}
	}
}
