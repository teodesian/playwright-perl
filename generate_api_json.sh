#!/bin/bash
pushd ../playwright
node utils/doclint/generateApiJson.js > ../playwright-perl/api.json
popd
