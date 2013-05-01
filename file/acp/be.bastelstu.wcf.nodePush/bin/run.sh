#!/bin/sh

cd `dirname $0`
if [ -d "bin" ]; then
	cd "../"
fi

echo "Installing dependencies"
/usr/bin/env npm install

cd "../lib"

/usr/bin/env node bootstrap.js
