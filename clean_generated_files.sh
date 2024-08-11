#!/bin/bash
rm api.json; true
rm bin/playwright_server; true
for module in $(git ls-files -o --exclude-standard lib/Playwright)
do
    rm $module; true
done
