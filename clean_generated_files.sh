#!/bin/bash
rm api.json; /bin/true
rm bin/playwright_server; /bin/true
for module in $(git ls-files -o --exclude-standard lib/Playwright)
do
    rm $module; /bin/true
done
