<?php
namespace wcf\system\event\listener;

/**
 * Signs the user id.
 * 
 * @author 	Tim Düsterhus
 * @copyright	2010-2014 Tim Düsterhus
 * @license	BSD 3-Clause License <http://opensource.org/licenses/BSD-3-Clause>
 * @package	be.bastelstu.wcf.nodePush
 * @subpackage	system.event.listener
 */
class TemplateEngineBeforeDisplayNodePushListener implements \wcf\system\event\IEventListener {
	/**
	 * @see	\wcf\system\event\IEventListener::execute()
	 */
	public function execute($eventObj, $className, $eventName) {
		if (!\wcf\system\nodePush\NodePushHandler::getInstance()->isEnabled()) return;
		
		\wcf\system\WCF::getTPL()->assign(array(
			'nodePushSignedUserID' => \wcf\util\Signer::createSignedString(\wcf\system\WCF::getUser()->userID)
		));
	}
}
