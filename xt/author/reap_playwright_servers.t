use strict;
use warnings;

BEGIN {
  unless ($ENV{AUTHOR_TESTING}) {
    print qq{1..0 # SKIP these tests are for testing by the author\n};
    exit;
   }
}

use Net::EmptyPort qw(empty_port);
use Playwright;
use Test2::V0;
use Cwd qw{abs_path};
use FindBin;

my $path2bin = abs_path("$FindBin::Bin/../../bin");
require("$path2bin/reap_playwright_servers");

$ENV{PATH} = "$path2bin:$ENV{PATH}";

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

