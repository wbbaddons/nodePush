<?php
namespace be\bastelstu\wcf\nodePush;

/**
 * Handles updates of nodePush.
 *
 * @author	Tim Düsterhus
 * @copyright	2012-2013 Tim Düsterhus
 * @license	BSD 3-Clause License <http://opensource.org/licenses/BSD-3-Clause>
 * @package	be.bastelstu.wcf.nodePush
 */
 // @codingStandardsIgnoreFile
final class Update {
	/**
	 * Restart service.
	 */
	public function execute() {
		\wcf\system\nodePush\NodePushHandler::getInstance()->sendMessage('be.bastelstu.wcf.nodePush._restart');
	}
}
$update = new Update();
$update->execute();
