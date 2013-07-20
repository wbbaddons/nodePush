#!/usr/bin/env php
<?php
namespace be\bastelstu\wcf\nodePush;
/**
 * Builds nodePush package.
 *
 * @author	Tim Düsterhus
 * @copyright	2012-2013 Tim Düsterhus
 * @license	BSD 3-Clause License <http://opensource.org/licenses/BSD-3-Clause>
 * @package	be.bastelstu.wcf.nodePush
 */
$packageXML = file_get_contents('package.xml');
preg_match('/<version>(.*?)<\/version>/', $packageXML, $matches);
echo "Building nodePush $matches[1]\n";
echo str_repeat("=", strlen("Building nodePush $matches[1]"))."\n";

echo <<<EOT
Cleaning up
-----------

EOT;
	if (file_exists('package.xml.old')) {
		file_put_contents('package.xml', file_get_contents('package.xml.old'));
		unlink('package.xml.old');
	}
	if (file_exists('file.tar')) unlink('file.tar');
	foreach (glob('file/acp/be.bastelstu.wcf.nodePush/lib/*.js') as $nodeFile) unlink($nodeFile);
	foreach (glob('file/js/*.js') as $jsFile) unlink($jsFile);
	if (file_exists('be.bastelstu.wcf.nodePush.tar')) unlink('be.bastelstu.wcf.nodePush.tar');
echo <<<EOT

Building JavaScript
-------------------

EOT;
foreach (glob('file/js/*.{litcoffee,coffee}', GLOB_BRACE) as $coffeeFile) {
	echo $coffeeFile."\n";
	passthru('coffee -c '.escapeshellarg($coffeeFile), $code);
	if ($code != 0) exit($code);
}
echo <<<EOT

Compressing JavaScript
----------------------

EOT;
foreach (glob('file/js/*.js', GLOB_BRACE) as $jsFile) {
	echo $jsFile."\n";
	passthru('uglifyjs '.escapeshellarg($jsFile).' --screw-ie8 -m -c --verbose --comments -o '.escapeshellarg(substr($jsFile, 0, -3).'.min.js'), $code);
	if ($code != 0) exit($code);
}
echo <<<EOT

Checking PHP for Syntax Errors
------------------------------

EOT;
	chdir('file');
	$check = null;
	$check = function ($folder) use (&$check) {
		if (is_file($folder)) {
			if (substr($folder, -4) === '.php') {
				passthru('php -l '.escapeshellarg($folder), $code);
				if ($code != 0) exit($code);
			}
			
			return;
		}
		$files = glob($folder.'/*');
		foreach ($files as $file) {
			$check($file);
		}
	};
	$check('.');
echo <<<EOT

Building file.tar
-----------------

EOT;
	passthru('tar cvf ../file.tar --exclude=file/js/*coffee --exclude=*.scss --exclude=.sass-cache --exclude=node_modules -- *', $code);
	if ($code != 0) exit($code);
echo <<<EOT

Building be.bastelstu.wcf.nodePush.tar
--------------------------------------

EOT;
	chdir('..');
	file_put_contents('package.xml.old', file_get_contents('package.xml'));
	file_put_contents('package.xml', preg_replace('~<date>\d{4}-\d{2}-\d{2}</date>~', '<date>'.date('Y-m-d').'</date>', file_get_contents('package.xml')));
	file_put_contents('package.xml', str_replace('</version>', '</version><!-- git id '.trim(shell_exec('git describe --always')).' -->', file_get_contents('package.xml')));
	passthru('tar cvf be.bastelstu.wcf.nodePush.tar --exclude=*.old --exclude=file --exclude=template --exclude=acptemplate --exclude=contrib -- *', $code);
	if (file_exists('package.xml.old')) {
		file_put_contents('package.xml', file_get_contents('package.xml.old'));
		unlink('package.xml.old');
	}
	if ($code != 0) exit($code);

if (file_exists('file.tar')) unlink('file.tar');
foreach (glob('file/acp/be.bastelstu.wcf.nodePush/lib/*.js') as $nodeFile) unlink($nodeFile);
foreach (glob('file/js/*.js') as $jsFile) unlink($jsFile);
