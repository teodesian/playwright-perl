#!/bin/bash
# Relies on the user having cloned the playwright repository in the directory directly adjacent to this repo
./clean_generated_files.sh
mkdir -p bin; true
pushd ../playwright > /dev/null
git pull -q
node utils/doclint/generateApiJson.js > ../playwright-perl/api.json
popd > /dev/null
cp playwright_server bin/playwright_server
API="$(<api.json)"
sed -i.bak -e '/%REPLACEME%/r api.json' -e 's/%REPLACEME%//g' bin/playwright_server
rm bin/playwright_server.bak

# Make which work on windows
cp bin/playwright_server bin/playwright_server.bat
