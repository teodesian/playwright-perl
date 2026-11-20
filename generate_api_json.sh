#!/bin/bash
# Relies on the user having cloned the playwright repository in the directory directly adjacent to this repo
here="$(cd "$(dirname "$0")" && pwd)"
playwright_src="$here/../playwright"
if [ ! -d "$playwright_src/utils/doclint" ]; then
    echo "generate_api_json.sh: no playwright checkout at $playwright_src" >&2
    echo "Playwright does not ship api.json on npm, so it is generated from their repository." >&2
    echo "Run ./fetch_playwright.sh, or clone it beside this one yourself." >&2
    exit 1
fi

./clean_generated_files.sh
mkdir -p bin; true
pushd "$playwright_src" > /dev/null
# fetch_playwright.sh clones a tag, which has no branch to pull.
if git symbolic-ref -q HEAD > /dev/null; then
    git pull -q
fi
if ! node utils/doclint/generateApiJson.js > "$here/api.json"; then
    echo "generate_api_json.sh: generateApiJson.js failed in $playwright_src" >&2
    exit 1
fi
popd > /dev/null
cp playwright_server bin/playwright_server
API="$(<api.json)"
sed -i.bak -e '/%REPLACEME%/r api.json' -e 's/%REPLACEME%//g' bin/playwright_server
rm bin/playwright_server.bak

# Make which work on windows
cp bin/playwright_server bin/playwright_server.bat
