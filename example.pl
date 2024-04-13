use strict;
use warnings;

use Data::Dumper;
use Playwright;
use Try::Tiny;
use Net::EmptyPort;
use Carp::Always;

NORMAL: {
    my $handle = Playwright->new( debug => 1 );

    # Open a new chrome instance
    my $browser = $handle->launch( headless => 1, type => 'firefox' );
    my $process = $handle->server( browser => $browser, command => 'process' );
    print "Browser PID: ".$process->{pid}."\n";

    # Open a tab therein
    my $page = $browser->newPage({ videosPath => 'video', acceptDownloads => 1 });

    # Test the spec method
    print Dumper($page->spec(),$page);

   # Browser contexts don't exist until you open at least one page.
    # You'll need this to grab and set cookies.
    my ($context) = @{$browser->contexts()};

    # Load a URL in the tab
    my $res = $page->goto('http://troglodyne.net', { waitUntil => 'networkidle' });
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
    my $actual_input = $page->select('input[name=like]');
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

    print "Download suggested filename\n";
    print $download->suggestedFilename()."\n";
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

    # Test out pusht/popt/try_until

    # Timeouts are in milliseconds
    Playwright::pusht($page,5000);
    my $checkpoint = time();
    my $element = Playwright::try_until($page, 'select', 'bogus-bogus-nothere');

    my $elapsed = time() - $checkpoint;
    Playwright::popt($page);
    print "Waited $elapsed seconds for timeout to drop\n";

    $checkpoint = time();
    $element = Playwright::try_until($page, 'select', 'bogus-bogus-nothere');
    $elapsed = time() - $checkpoint;
    print "Waited $elapsed seconds for timeout to drop\n";

    # Try out the API testing extensions
    print "HEAD http://troglodyne.net : \n";
    my $fr = $page->request;
    my $resp = $fr->fetch("http://troglodyne.net", { method => "HEAD" });
    print Dumper($resp->headers());
    print "200 OK\n" if $resp->status() == 200;

    # Test that we can do stuff with with the new locator API.
    my $loc = $page->locator('body');
    my $innerTubes = $loc->allInnerTexts();
    print Dumper($innerTubes);
    my $image = $page->getByAltText('picture');
    print Dumper($image);

    # Save a video now that we are done
    my $bideo = $page->video;

    # IT IS IMPORTANT TO CLOSE THE PAGE FIRST OR THIS WILL HANG!
    $page->close();
    my $vidpath = $bideo->saveAs('video/example.webm');
}

# Example of using persistent mode / remote hosts
OPEN: {
    my $handle  = Playwright->new( debug => 1 );
    my $handle2 = Playwright->new( debug => 1, host => 'localhost', port => $handle->{port} );

    my $browser = $handle2->launch( headless => 1, type => 'firefox' );
    my $process = $handle2->server( browser => $browser, command => 'process' );
    print "Browser PID: ".$process->{pid}."\n";

}

# Example of connecting to remote CDP sessions
CDP: {
    local $SIG{HUP} = 'IGNORE';

    sub kill_krom_and_die {
        my ($in, $msg) = @_;
        kill_krom($in);
        die $msg;
    }

    sub kill_krom {
        my ($in) = @_;
        kill HUP => -getpgrp();
        close $in;
    }

    my $port = Net::EmptyPort::empty_port();

    my $pid = fork // die("Could not fork");
    if (!$pid) {
        open(my $stdin, '|-', qq{chromium-browser --remote-debugging-port=$port --headless}) or die "Could not open chromium-browser to test!";
        print "Waiting for cdp server on port $port to come up...\n";
        Net::EmptyPort::wait_port( $port, 10 )
          or kill_krom_and_die($stdin, "Server never came up after 10s!");
        print "done\n";

        #XXX not clear that this doesn't want an http uri instead? idk
        my $handle = Playwright->new( debug => 1, cdp_uri => "ws://127.0.0.1:$port" );

        # Open a new chrome instance
        my $browser = $handle->launch( headless => 1, type => 'chrome' );

        # Open a tab therein
        my $page = $browser->newPage({ videosPath => 'video', acceptDownloads => 1 });

        # Load a URL in the tab
        my $res = $page->goto('http://troglodyne.net', { waitUntil => 'networkidle' });
        print Dumper($res->status(), $browser->version());

        $handle->quit();

        #XXX OF COURSE chrome responds correctly to ESPIPE and SIGCHLD, why wouldn't it
        kill_krom($stdin);
        exit 0;
    } else {
        # If it can't get done in 20s, it ain't getting done
        foreach (0..20) {
            last unless waitpid( $pid, 1) == 0;
            sleep 1;
        }
    }
    print "All Done!\n\n";
}

# Clean up, since we left survivors
require './bin/reap_playwright_servers';
Playwright::ServerReaper::main();
0;
