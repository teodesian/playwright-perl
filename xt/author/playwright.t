use strict;
use warnings;

use Data::Dumper;
use Playwright;
use Try::Tiny;
use Net::EmptyPort;
use Carp::Always;
use Test2::V0;

BEGIN {
   unless ($ENV{AUTHOR_TESTING}) {
     print qq{1..0 # SKIP these tests are for testing by the author\n};
     exit;
    }
}

my $handle = Playwright->new( debug => 1 );

# Open a new chrome instance
my $browser = $handle->launch( headless => 1, type => 'firefox' );
my $process = $handle->server( browser => $browser, command => 'process' );
note "Browser PID: ".$process->{pid}."\n";

# Open a tab therein
my $page = $browser->newPage({ videosPath => 'video', acceptDownloads => 1 });

# Test the spec method
ok($page->spec(), "Was able to open a browser and fetch the playwright spec");

# Browser contexts don't exist until you open at least one page.
# You'll need this to grab and set cookies.
my ($context) = @{$browser->contexts()};
ok($context, "Got a browser context");

# Load a URL in the tab
my $res = $page->goto('http://troglodyne.net', { waitUntil => 'networkidle' });
ok($res->status(), "Was able to fetch a webpage");
note $browser->version();

# Put your hand in the jar
my $cookies = $context->cookies();
ok($cookies, "was able to read the cookie jar");

# Grab the main frame, in case this is a frameset
my $frameset = $page->mainFrame();
ok($frameset->childFrames(), "Was able to grab the frameset");

# Run some JS
my $fun = "
    var input = arguments[0];
    return {
        width: document.documentElement.clientWidth,
        height: document.documentElement.clientHeight,
        deviceScaleFactor: window.devicePixelRatio,
        arg: input
    };";
my $result = $page->evaluate($fun, 'zippy');
ok($result->{width}, "Was able to evaulate Javascript");

# Read the console
$page->on('console',"return [...arguments]");

my $promise = $page->waitForEvent('console');
#XXX this *can* race
sleep 1;
$page->evaluate("console.log('hug')");
my $console_log = $handle->await( $promise );
is($console_log->text(), "hug", "Can read the JS console");

# Use a selector to find which input is visible and type into it
# Ideally you'd use a better selector to solve this problem, but this is just showing off
my $inputs = $page->selectMulti('input');
ok(@$inputs, "Able to grab inputs on the page");

foreach my $input (@$inputs) {
    try {
        # Pretty much a brute-force approach here, again use a better pseudo-selector instead like :visible
        $input->fill('tickle', { timeout => 250 } );
    } catch {
        note "Element not visible, skipping...\n";
    }
}

# Said better selector
my $actual_input = $page->select('input[name=like]');
$actual_input->fill('whee');

# Ensure we can grab the parent (convenience)
ok($actual_input->{parent}, "Can fetch parent of any element");

# Take screen of said element
ok($actual_input->screenshot({ path => 'test.jpg' }), "Can take screenshot");

# Fiddle with HIDs
my $mouse = $page->mouse;
is($mouse->move( 0, 0 ), undef, "Can move mouse");
my $keyboard = $page->keyboard();
is($keyboard->type('F12'), undef, "Can type keys");

# Start to do some more advanced actions with the page
use FindBin;
use Cwd qw{abs_path};
my $pg = abs_path("$FindBin::Bin/test.html");

# Handle dialogs on page start, and dialog after dialog
# NOTE -- the 'load' event won't fire until the dialog is dismissed in some browsers
$promise = $page->waitForEvent('dialog');
$page->goto("file://$pg", { waitUntil => 'networkidle' });

my $dlg = $handle->await($promise);
$promise = $page->waitForEvent('dialog');
is($dlg->dismiss(), undef, "Can dismiss dialog");
$dlg = $handle->await($promise);
is($dlg->accept(), undef, "Can accept dialog");

# Download stuff -- note this requries acceptDownloads = true in the page open
# NOTE -- the 'download' event fires unreliably, as not all browsers properly obey the 'download' property in hrefs.
# Chrome, for example would choke here on an intermediate dialog.
$promise = $page->waitForEvent('download');
sleep 1;
$page->select('#d-lo')->click();

my $download = $handle->await( $promise );

print "Download suggested filename\n";
print $download->suggestedFilename()."\n";
is($download->saveAs('test2.jpg'), undef, "can download stuff");

# Fiddle with file inputs
my $choochoo = $page->waitForEvent('filechooser');
$page->select('#drphil')->click();
my $chooseu = $handle->await( $choochoo );
is($chooseu->setFiles('test.jpg'), undef, "Can interact with file picker");

# Make sure we can do child selectors
my $parent = $page->select('body');
my $child = $parent->select('#drphil');
ok($child, "Can get child elements");

# Test out pusht/popt/try_until

# Timeouts are in milliseconds
Playwright::pusht($page,5000);
my $checkpoint = time();
my $element = Playwright::try_until($page, 'select', 'bogus-bogus-nothere');

my $elapsed = time() - $checkpoint;
Playwright::popt($page);
note "Waited $elapsed seconds for timeout to drop\n";

$checkpoint = time();
$element = Playwright::try_until($page, 'select', 'bogus-bogus-nothere');
$elapsed = time() - $checkpoint;
note "Waited $elapsed seconds for timeout to drop\n";

pass("Can wait on timeouts");

# Try out the API testing extensions
print "HEAD http://troglodyne.net : \n";
my $fr = $page->request;
my $resp = $fr->fetch("http://troglodyne.net", { method => "HEAD" });
ok($resp->headers(), "Can dump headers from HEAD method");
is($resp->status(), 200, "Good status from headers");

# Test that we can do stuff with with the new locator API.
my $loc = $page->locator('body');
my $innerTubes = $loc->allInnerTexts();
ok($innerTubes, "Can get text via locators");
my $image = $page->getByAltText('picture');
ok($image, "Can get image by alt text");

# Save a video now that we are done
my $bideo = $page->video;

# IT IS IMPORTANT TO CLOSE THE PAGE FIRST OR THIS WILL HANG!
$page->close();
my $vidpath = $bideo->saveAs('video/example.webm');
is($vidpath, undef, "Can save video");
done_testing();
