#!/bin/bash
# generate_api_json.sh reads the playwright repository from ../playwright.
# When there is none, clone the release that npm installed, so api.json describes that release.
here="$(cd "$(dirname "$0")" && pwd)"
playwright_src="$here/../playwright"
if [ -d "$playwright_src/utils/doclint" ]; then
    exit 0
fi

version="$(node -p 'require("playwright/package.json").version')" || {
    echo "fetch_playwright.sh: cannot read the version of the installed playwright; run npm i first" >&2
    exit 1
}
if ! git -c advice.detachedHead=false clone -q --depth 1 --branch "v$version" https://github.com/microsoft/playwright.git "$playwright_src"; then
    echo "fetch_playwright.sh: could not clone tag v$version of microsoft/playwright into $playwright_src" >&2
    exit 1
fi
