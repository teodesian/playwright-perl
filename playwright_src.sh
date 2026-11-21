# Sourced by fetch_playwright.sh and generate_api_json.sh, after each sets $here
# to the directory of this checkout.  Sets $playwright_src to the playwright
# repository that api.json is generated from.
#
# An author's checkout beside this one comes first.  Otherwise it is the release
# that fetch_playwright.sh clones into .playwright, inside this checkout, so a
# build writes nothing outside the directory that it was started in.
playwright_src="$here/../playwright"
if [ ! -d "$playwright_src/utils/doclint" ]; then
    playwright_src="$here/.playwright"
fi
