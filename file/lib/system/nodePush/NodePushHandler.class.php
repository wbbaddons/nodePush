<?php
namespace wcf\system\nodePush;
use wcf\util\StringUtil;

/**
 * Push Handler.
 *
 * @author	Tim Düsterhus
 * @copyright	2012-2013 Tim Düsterhus
 * @license	BSD 3-Clause License <http://opensource.org/licenses/BSD-3-Clause>
 * @package	be.bastelstu.wcf.nodePush
 * @subpackage	system.nodePush
 */
class NodePushHandler extends \wcf\system\SingletonFactory {
	/**
	 * Array of messages to send at shutdown.
	 * 
	 * @var	array
	 */
	private $deferred = array();
	
	/**
	 * Returns whether the push server is enabled (i.e. `NODEPUSH_HOST` is set).
	 * 
	 * @return	boolean
	 */
	public function isEnabled() {
		return (boolean) NODEPUSH_HOST;
	}
	
	/**
	 * Returns whether the push server appears running (i.e. one can connect to it).
	 * Output may not 100% correct, but is pretty reliable.
	 * 
	 * @return	boolean
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
		if (StringUtil::startsWith($this->getSocketPath(), 'unix://')) {
			if (!file_exists(StringUtil::substring($this->getSocketPath(), 7))) return false;
			if (!is_writable(StringUtil::substring($this->getSocketPath(), 7))) return false;
		}
		
		return stream_socket_client($this->getSocketPath(), $errno, $errstr, 1);
	}
	
	/**
	 * Sends a message to the connected clients. Returns `true` on success and `false`
	 * otherwise.
	 * 
	 * If `$userIDs` is an empty array the message will be sent to every connected client. 
	 * Otherwise the message will only be sent to clients with the given userID.
	 * 
	 * ATTENTION: Do NOT (!) send any security related information via sendMessage.
	 * The userID given can easily be forged, by a malicious client!
	 * 
	 * @param	string			$message
	 * @param	array<integer>	$userIDs
	 * @return	boolean
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
	 * Registers a deferred message. Returns `true` on any well-formed message and `false`
	 * otherwise.
	 * Deferred messages will be sent on shutdown. This can be useful if your handler depends
	 * on data that may not be written to database yet or to achieve a better performance as the
	 * page is delivered first.
	 * 
	 * ATTENTION: Use this method only if your messages are not critical as you cannot check
	 * whether your message was delivered successfully.
	 * ATTENTION: Do NOT (!) send any security related information via sendDeferredMessage.
	 * The userID given can easily be forged, by a malicious client!
	 * 
	 * @see	\wcf\system\nodePush\NodePushHandler::sendDeferredMessage()
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
	 * Sends out the deferred messages.
	 */
	public function __destruct() {
		foreach ($this->deferred as $data) {
			$this->sendMessage($data['message'], $data['userIDs']);
		}
	}
	
	/**
	 * Returns the path to the "inbound" socket file.
	 * 
	 * @return	string
	 */
	public function getSocketPath() {
		return str_replace('{WCF_DIR}', WCF_DIR, NODEPUSH_SOCKET);
	}
}
