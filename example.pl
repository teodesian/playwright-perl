use strict;
use warnings;

use Data::Dumper;
use JSON::PP;
use Playwright;

use Try::Tiny;

my $handle = Playwright->new();

# Open a new chrome instance
my $browser = $handle->launch( headless => JSON::PP::false, type => 'chrome' );

# Open a tab therein
my $page = $browser->newPage();

# Browser contexts don't exist until you open at least one page.
# You'll need this to grab and set cookies.
my ($context) = @{$browser->contexts()};

# Load a URL in the tab
my $res = $page->goto('http://google.com', { waitUntil => 'networkidle' });
print Dumper($res->status(), $browser->version());

# Grab the main frame, in case this is a frameset
my $frameset = $page->mainFrame();
print Dumper($frameset->childFrames());

# Use a selector to find which input is visible and type into it
# Ideally you'd use a better selector to solve this problem, but this is just showing off
my $inputs = $page->selectMulti('input');

foreach my $input (@$inputs) {
    try {
        # Pretty much a brute-force approach here, again use a better pseudo-selector instead like :visible
        $input->fill('whee', { timeout => 250 } );
    } catch {
        print "Element not visible, skipping...\n";
    }
}

# Said better selector
my $actual_input = $page->select('input[name=q]');
$actual_input->fill('whee');


#my $cookies = $context->cookies();
