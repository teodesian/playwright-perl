#!/bin/bash
# Relies on the user having cloned the playwright repository in the directory directly adjacent to this repo
./clean_generated_files.sh
mkdir bin; /bin/true
pushd ../playwright
git pull
node utils/doclint/generateApiJson.js > ../playwright-perl/api.json
popd
cp playwright_server bin/playwright_server
API="$(<api.json)"
sed -i -e '/%REPLACEME%/r api.json' -e 's/%REPLACEME%//g' bin/playwright_server
# Make which work on windows
cp bin/playwright_server bin/playwright_server.bat
