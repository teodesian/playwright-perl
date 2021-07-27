#!/bin/bash
pushd ../playwright
git pull
node utils/doclint/generateApiJson.js > ../playwright-perl/api.json
popd
