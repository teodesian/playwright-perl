use strict;
use warnings;

use Test2::V0;
use Test2::Tools::Explain;
use Playwright;
use Playwright::Util;

use File::Which;
use Net::EmptyPort;

BEGIN {
    unless ($ENV{AUTHOR_TESTING}) {
        print qq{1..0 # SKIP these tests are for testing by the author\n};
        exit;
    }
    $ENV{NODE_PATH} //= '';
    $ENV{NODE_PATH} = Playwright::Util::find_node_modules().":$ENV{NODE_PATH}";
}

my $chromium = File::Which::which('chromium') || File::Which::which('chromium-browser');
die "Chromium not installed on this host." unless $chromium;

my $port = Net::EmptyPort::empty_port();

open(my $stdin, '|-', qq{$chromium --remote-debugging-port=$port --headless}) or die "Could not open chromium-browser to test!";
note "Waiting for cdp server on port $port to come up...";
Net::EmptyPort::wait_port( $port, 10 )
  or die( "Server never came up after 10s!");
note "done";

#XXX not clear that this doesn't want an http uri instead? idk
my $handle = Playwright->new( debug => 1, cdp_uri => "http://127.0.0.1:$port" );

# Open a new chrome instance
my $browser = $handle->launch( headless => 1, type => 'chrome' );

# Open a tab therein
my $page = $browser->newPage({ acceptDownloads => 1 });

# Load a URL in the tab
my $res = $page->goto('http://troglodyne.net', { waitUntil => 'networkidle' });
ok($res->status(), "Request was successful") or diag explain Dumper($res->status(), $browser->version());

my ($context) = @{$browser->contexts()};

# Only reliable way to close chrome
my $cdp = $context->newCDPSession($page);
$cdp->send('Browser.close');

done_testing();
