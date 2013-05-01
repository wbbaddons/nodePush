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
	 * @return boolean|resource
	 */
	private function connect() {
		if (StringUtil::startsWith($this->getSocketPath(), 'unix://')) {
			if (!file_exists(StringUtil::substring($this->getSocketPath(), 7))) return false;
			if (!is_writable(StringUtil::substring($this->getSocketPath(), 7))) return false;
		}
		
		return stream_socket_client($this->getSocketPath(), $errno, $errstr, 1);
	}
	
	/**
	 * Sends a message to all connected clients. Returns true on success
	 * and false otherwise.
	 * 
	 * @param	string		$message
	 * @return	boolean
	 */
	public function sendMessage($message) {
		if (!$this->isEnabled()) return false;
		if (!\wcf\data\package\Package::isValidPackageName($message)) return false;
		
		try {
			$sock = $this->connect();
			if ($sock === false) return false;
			
			$success = fwrite($sock, StringUtil::trim($message));
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
	 * Returns the path to the SOCKET file.
	 */
	public function getSocketPath() {
		return str_replace('{WCF_DIR}', WCF_DIR, NODEPUSH_SOCKET);
	}
}
