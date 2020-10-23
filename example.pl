use strict;
use warnings;

use Data::Dumper;
use Playwright;

my ($browser,$page) = Playwright->new( browser => 'chrome', visible => 1 );

my $res = $page->goto('http://google.com', { waitUntil => 'networkidle' });
print Dumper($res->status(), $browser->version());
my $frameset = $page->mainFrame();
print Dumper($frameset->{guid});
print Dumper($frameset->childFrames());
