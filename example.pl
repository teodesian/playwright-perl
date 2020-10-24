use strict;
use warnings;

use Data::Dumper;
use JSON::PP;
use Playwright;

my $handle = Playwright->new();
my $browser = $handle->launch( headless => JSON::PP::false, type => 'chrome' );
my $page = $browser->newPage();
my $res = $page->goto('http://google.com', { waitUntil => 'networkidle' });
print Dumper($res->status(), $browser->version());
my $frameset = $page->mainFrame();
print Dumper($frameset->childFrames());
