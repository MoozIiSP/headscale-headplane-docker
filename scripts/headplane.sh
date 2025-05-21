#!/bin/sh
set -e

cd /app/headplane/
exec node ./build/server/index.js