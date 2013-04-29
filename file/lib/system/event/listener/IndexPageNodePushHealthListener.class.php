<?php
namespace wcf\system\event\listener;

/**
 * Shows nodePush health on acp IndexPage.
 * 
 * @author	Tim Düsterhus
 * @copyright	2012-2013 Tim Düsterhus
 * @license	BSD 3-Clause License <http://opensource.org/licenses/BSD-3-Clause>
 * @package	be.bastelstu.wcf.nodePush
 * @subpackage	system.event.listener
 */
class IndexPageNodePushHealthListener implements \wcf\system\event\IEventListener {
	/**
	 * @see	wcf\system\event\IEventListener::execute()
	 */
	public function execute($eventObj, $className, $eventName) {
		if (!\wcf\system\nodePush\NodePushHandler::getInstance()->isEnabled()) return;
		if (\wcf\system\nodePush\NodePushHandler::getInstance()->isRunning()) return;
		
		$eventObj->healthDetails['error'][] = \wcf\system\WCF::getLanguage()->getDynamicVariable('wcf.acp.index.health.nodePushDead');
	}
}
