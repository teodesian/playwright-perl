use strict;
use warnings;

use Data::Dumper;
use Playwright;

my ($browser) = Playwright->new( browser => 'chrome', visible => 1 );
my $page = $browser->newPage();
my $res = $page->goto('http://google.com', { waitUntil => 'networkidle' });
print Dumper($res->status(), $browser->version());
my $frameset = $page->mainFrame();
print Dumper($frameset->childFrames());
