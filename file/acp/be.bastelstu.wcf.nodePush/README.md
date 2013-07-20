nodePush
========

This directory contains nodePush.

DO NOT DELETE THIS DIRECTORY!

How to setup?
-------------

1. Rename `config.js.template` to `config.js`
2. Check the settings. It most cases the defaults are fine
3. Run `npm start`. It will load all dependencies and then start the service.

ATTENTION: Don't use `npm start` as root!!
Use `node_modules/.bin/coffee app.coffee` after setting `disableAutorestart` to `true`. Have a look at `user`, `group` and `chroot` as well.