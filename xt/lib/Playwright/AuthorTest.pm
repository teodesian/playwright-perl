package Playwright::AuthorTest;

use strict;
use warnings;

use File::Basename();
use Playwright::Util;

# Common setup for the author tests: skip unless AUTHOR_TESTING, and point NODE_PATH and PATH at this checkout or build.
# Load it before Playwright, which picks node and playwright_server, and checks that they run, when it loads.
sub import {
    unless ( $ENV{AUTHOR_TESTING} ) {
        print qq{1..0 # SKIP these tests are for testing by the author\n};
        exit;
    }
    $ENV{NODE_PATH} //= '';
    $ENV{NODE_PATH} = Playwright::Util::find_node_modules() . ":$ENV{NODE_PATH}";

    # An installed playwright_server from an older release would otherwise be first on PATH.
    my $built = Playwright::Util::find_playwright_server();
    $ENV{PATH} = File::Basename::dirname($built) . ":$ENV{PATH}" if -x $built;
    return;
}

1;
