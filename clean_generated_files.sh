#!/bin/bash
rm -f api.json; true
rm -f bin/playwright_server; true
for module in $(git ls-files -o --exclude-standard lib/Playwright)
do
    rm -f $module; true
done
