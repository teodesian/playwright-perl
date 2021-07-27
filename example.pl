use strict;
use warnings;

use Data::Dumper;

use Playwright;

use Try::Tiny;

my $handle = Playwright->new( debug => 1 );

# Open a new chrome instance
my $browser = $handle->launch( headless => 0, type => 'firefox' );

# Open a tab therein
my $page = $browser->newPage({ videosPath => 'video', acceptDownloads => 1 });
my $bideo = $page->video;

my $vidpath = $bideo->path;
print "Video Path: $vidpath\n";

# Browser contexts don't exist until you open at least one page.
# You'll need this to grab and set cookies.
my ($context) = @{$browser->contexts()};

# Load a URL in the tab
my $res = $page->goto('http://google.com', { waitUntil => 'networkidle' });
print Dumper($res->status(), $browser->version());

# Put your hand in the jar
my $cookies = $context->cookies();
print Dumper($cookies);

# Grab the main frame, in case this is a frameset
my $frameset = $page->mainFrame();
print Dumper($frameset->childFrames());

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
print Dumper($result);

# Read the console
$page->on('console',"return [...arguments]");

my $promise = $page->waitForEvent('console');
#XXX this *can* race
sleep 1;
$page->evaluate("console.log('hug')");
my $console_log = $handle->await( $promise );

print "Logged to console: '".$console_log->text()."'\n";

# Use a selector to find which input is visible and type into it
# Ideally you'd use a better selector to solve this problem, but this is just showing off
my $inputs = $page->selectMulti('input');

foreach my $input (@$inputs) {
    try {
        # Pretty much a brute-force approach here, again use a better pseudo-selector instead like :visible
        $input->fill('tickle', { timeout => 250 } );
    } catch {
        print "Element not visible, skipping...\n";
    }
}

# Said better selector
my $actual_input = $page->select('input[name=q]');
$actual_input->fill('whee');

# Ensure we can grab the parent (convenience)
print "Got Parent: ISA ".ref($actual_input->{parent})."\n";

# Take screen of said element
$actual_input->screenshot({ path => 'test.jpg' });

# Fiddle with HIDs
my $mouse = $page->mouse;
$mouse->move( 0, 0 );
my $keyboard = $page->keyboard();
$keyboard->type('F12');

# Start to do some more advanced actions with the page
use FindBin;
use Cwd qw{abs_path};
my $pg = abs_path("$FindBin::Bin/at/test.html");

# Handle dialogs on page start, and dialog after dialog
# NOTE -- the 'load' event won't fire until the dialog is dismissed in some browsers
$promise = $page->waitForEvent('dialog');
$page->goto("file://$pg", { waitUntil => 'networkidle' });

my $dlg = $handle->await($promise);
$promise = $page->waitForEvent('dialog');
$dlg->dismiss();
$dlg = $handle->await($promise);
$dlg->accept();

# Download stuff -- note this requries acceptDownloads = true in the page open
# NOTE -- the 'download' event fires unreliably, as not all browsers properly obey the 'download' property in hrefs.
# Chrome, for example would choke here on an intermediate dialog.
$promise = $page->waitForEvent('download');
$page->select('#d-lo')->click();

my $download = $handle->await( $promise );

$download->saveAs('test2.jpg');

# Fiddle with file inputs
my $choochoo = $page->waitForEvent('filechooser');
$page->select('#drphil')->click();
my $chooseu = $handle->await( $choochoo );
$chooseu->setFiles('test.jpg');

# Make sure we can do child selectors
my $parent = $page->select('body');
my $child = $parent->select('#drphil');
print ref($child)."\n";

