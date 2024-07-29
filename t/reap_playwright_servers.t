use strict;
use warnings;

use Net::EmptyPort qw(empty_port);
use Playwright;
use Test2::V0;

my $handle = Playwright->new( cleanup => 0 );
my $browser = $handle->launch( headless => 0, type => 'chrome' );
is ($handle->{ cleanup }, 0, "Cleanup option set correctly" );

my $port = Net::EmptyPort::empty_port();
my $handle2 = Playwright->new( port => $port );
my $browser2 = $handle2->launch( headless => 0, type => 'chrome' );
is ($handle2->{ cleanup }, 0, "Cleanup option set correctly" );
is ($handle2->{ port }, $port, "Port option set correctly" );

my $result = `reap_playwright_servers`;
like ($result, qr/Instructing playwright_server process \d+ listening on $handle->{ port } to shut down/, "Reaping first server" );
like ($result, qr/Instructing playwright_server process \d+ listening on $handle2->{ port } to shut down/, "Reaping second server" );

is( `reap_playwright_servers`, '', "No servers running" );

done_testing();

