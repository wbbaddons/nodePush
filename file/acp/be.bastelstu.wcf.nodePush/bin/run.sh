#!/bin/sh

cd `dirname $0`

if [ -z "$NODE_ENV" ]; then
	NODE_ENV=production
fi
export NODE_ENV

echo "Installing dependencies"
/usr/bin/env npm install

cd "../lib"
/usr/bin/env node bootstrap.js "$@"
