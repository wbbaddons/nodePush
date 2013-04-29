<?php
namespace wcf\system\nodePush;

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
	 * Filename of the socket.
	 * 
	 * @var string
	 */
	const SOCKET = 'inbound.sock';
	
	/**
	 * Regex to validate messages.
	 * 
	 * @var \wcf\system\Regex
	 */
	protected $messageRegex = null;
	
	/**
	 * @see	\wcf\system\SingletonFactory::init()
	 */
	protected function init() {
		$this->messageRegex = new \wcf\system\Regex('^[a-zA-Z0-9-_.]+$');
	}
	
	/**
	 * Returns whether the push server is enabled.
	 * 
	 * @return	boolean
	 */
	public function isEnabled() {
		return (boolean) NODEPUSH_HOST;
	}
	
	/**
	 * Returns whether the push server appears running. Output may not
	 * 100% correct, but is pretty reliable.
	 * 
	 * @return	boolean
	 */
	public function isRunning() {
		if (!$this->isEnabled()) return false;
		if (!file_exists($this->getSocketPath())) return false;
		if (!is_writable($this->getSocketPath())) return false;
		
		return true;
	}
	
	/**
	 * Sends a message to all connected clients. Returns true on success
	 * and false otherwise.
	 * 
	 * @param	string		$message
	 * @return	boolean
	 */
	public function sendMessage($message) {
		if (!$this->isRunning()) return false;
		if (!$this->messageRegex->match($message)) return false;
		
		try {
			$sock = stream_socket_client('unix://'.$this->getSocketPath(), $errno, $errstr, 1);
			$success = fwrite($sock, trim($message));
			fclose($sock);
		}
		catch (\Exception $e) {
			if ($sock) fclose($sock);
			// gotta catch 'em all
			return false;
		}
		
		return (boolean) $success;
	}
	
	/**
	 * Returns the path to the SOCKET file.
	 */
	public function getSocketPath() {
		return WCF_DIR.'acp/be.bastelstu.wcf.nodePush/'.self::SOCKET;
	}
}
