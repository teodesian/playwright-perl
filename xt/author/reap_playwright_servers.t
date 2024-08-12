use strict;
use warnings;

use Net::EmptyPort qw(empty_port);
use Playwright;
use Test2::V0;
use Cwd qw{abs_path};
use FindBin;

BEGIN {
    unless ($ENV{AUTHOR_TESTING}) {
        print qq{1..0 # SKIP these tests are for testing by the author\n};
        exit;
    }
    $ENV{NODE_PATH} //= '';
    $ENV{NODE_PATH} = Playwright::Util::find_node_modules().":$ENV{NODE_PATH}";
}

my $path2bin = Playwright::Util::_find("bin/reap_playwright_servers");
require($path2bin);

my $handle = Playwright->new( cleanup => 0 );
my $browser = $handle->launch( headless => 1, type => 'chrome' );
is ($handle->{ cleanup }, 0, "Cleanup option set correctly" );

my $port = Net::EmptyPort::empty_port();
my $handle2 = Playwright->new( port => $port );
my $browser2 = $handle2->launch( headless => 1, type => 'chrome' );
is ($handle2->{ cleanup }, 0, "Cleanup option set correctly" );
is ($handle2->{ port }, $port, "Port option set correctly" );

my $result = Playwright::ServerReaper::main();
like ($result, 0, "Servers reaped" );

done_testing();

