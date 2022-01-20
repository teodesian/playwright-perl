package Playwright;

use strict;
use warnings;

#ABSTRACT: Perl client for Playwright
use 5.006;
use v5.28.0;    # Before 5.006, v5.10.0 would not be understood.

use File::ShareDir();
use File::Basename();
use Cwd();
use LWP::UserAgent();
use Sub::Install();
use Net::EmptyPort();
use JSON::MaybeXS();
use File::Which();
use Capture::Tiny qw{capture_merged capture_stderr};
use Carp qw{confess};

use Playwright::Base();
use Playwright::Util();

# Stuff closet full of skeletons at BEGIN time
use Playwright::ModuleList();

no warnings 'experimental';
use feature qw{signatures};

=head1 SYNOPSIS

    use Playwright;

    my $handle = Playwright->new();
    my $browser = $handle->launch( headless => 0, type => 'chrome' );
    my $page = $browser->newPage();
    my $res = $page->goto('http://somewebsite.test', { waitUntil => 'networkidle' });
    my $frameset = $page->mainFrame();
    my $kidframes = $frameset->childFrames();

    # Grab us some elements
    my $body = $page->select('body');

    # You can also get the innerText
    my $text = $body->textContent();
    $body->click();
    $body->screenshot();

    my $kids = $body->selectMulti('*');

=head1 DESCRIPTION

Perl interface to a lightweight node.js webserver that proxies commands runnable by Playwright.
Checks and automatically installs a copy of the node dependencies in the local folder if needed.

Currently understands commands you can send to all the playwright classes defined in api.json (installed wherever your OS puts shared files for CPAN distributions).

See L<https://playwright.dev/versions> and drill down into your relevant version (run `npm list playwright` )
for what the classes do, and their usage.

All the classes mentioned there will correspond to a subclass of the Playwright namespace.  For example:

    # ISA Playwright
    my $playwright = Playwright->new();
    # ISA Playwright::BrowserContext
    my $ctx = $playwright->newContext(...);
    # ISA Playwright::Page
    my $page = $ctx->newPage(...);
    # ISA Playwright::ElementHandle
    my $element = $ctx->select('body');

See example.pl for a more thoroughly fleshed-out display on how to use this module.

=head2 Getting Started

When using the playwright module for the first time, you may be told to install node.js libraries.
It should provide you with instructions which will get you working right away.

However, depending on your node installation this may not work due to dependencies for node.js not being in the expected location.
To fix this, you will need to update your NODE_PATH environment variable to point to the correct location.

=head3 Node Versions

playwright itself tends to need the latest version of node to work properly.
It is recommended that you use nvm to get a hold of this:

L<https://github.com/nvm-sh/nvm>

From there it's recommended you use the latest version of node:

    nvm install node
    nvm use node

=head2 Questions?

Feel free to join the Playwright slack server, as there is a dedicated #playwright-perl channel which I, the module author, await your requests in.
L<https://aka.ms/playwright-slack>

=head2 Documentation for Playwright Subclasses

The documentation and names for the subclasses of Playwright follow the spec strictly:

Playwright::BrowserContext => L<https://playwright.dev/docs/api/class-browsercontext>
Playwright::Page           => L<https://playwright.dev/docs/api/class-page>
Playwright::ElementHandle  => L<https://playwright.dev/docs/api/class-elementhandle>

...And so on.  These classes are automatically generated during module build based on the spec hash built by playwright.
See generate_api_json.sh and generate_perl_modules.pl if you are interested in how this sausage is made.

You can check what methods are installed for each subclass by doing the following:

    use Data::Dumper;
    print Dumper($instance->{spec});

There are two major exceptions in how things work versus the upstream Playwright documentation, detailed below in the C<Selectors> section.

=head2 Selectors

The selector functions have to be renamed from starting with $ for obvious reasons.
The renamed functions are as follows:

=over 4

=item $ => select

=item $$ => selectMulti

=item $eval => evaluate

=item $$eval => evalMulti

=back

These functions are present as part of the Page, Frame and ElementHandle classes.

=head2 Scripts

The evaluate() and evaluateHandle() functions can only be run in string mode.
To maximize the usefulness of these, I have wrapped the string passed with the following function:

    const fun = new Function (toEval);
    args = [
        fun,
        ...args
    ];

As such you can effectively treat the script string as a function body.
The same restriction on only being able to pass one arg remains from the upstream:
L<https://playwright.dev/docs/api/class-page#pageevalselector-pagefunction-arg>

You will have to refer to the arguments array as described here:
L<https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Functions/arguments>

You can also pass Playwright::ElementHandle objects as returned by the select() and selectMulti() routines.
They will be correctly translated into DOMNodes as you would get from the querySelector() javascript functions.

Calling evaluate() and evaluateHandle() on Playwright::Element objects will automatically pass the DOMNode as the first argument to your script.
See below for an example of doing this.

=head3 example of evaluate()

    # Read the console
    $page->on('console',"return [...arguments]");

    my $promise = $page->waitForEvent('console');
    #TODO This request can race, the server framework I use to host the playwright spec is *not* FIFO (YET)
    sleep 1;
    $page->evaluate("console.log('hug')");
    my $console_log = $handle->await( $promise );

    print "Logged to console: '".$console_log->text()."'\n";

    # Convenient usage of evaluate on ElementHandles
    # We pass the element itself as the first argument to the JS arguments array for you
    $element->evaluate('arguments[0].style.backgroundColor = "#FF0000"; return 1;');


=head2 Asynchronous operations

The waitFor* methods defined on various classes fork and exec, waiting on the promise to complete.
You will need to wait on the result of the backgrounded action with the await() method documented below.

    # Assuming $handle is a Playwright object
    my $async = $page->waitForEvent('console');
    $page->evaluate('console.log("whee")');
    my $result = $handle->await( $async );
    my $logged = $result->text();

=head2 Getting Object parents

Some things, like elements naturally are children of the pages in which they are found.
Sometimes this can get confusing when you are using multiple pages, especially if you let the ref to the page go out of scope.
Don't worry though, you can access the parent attribute on most Playwright::* objects:

    # Assuming $element is a Playwright::ElementHandle
    my $page = $element->{parent};


=head2 Firefox Specific concerns

By default, firefox will open PDFs in a pdf.js window.
To suppress this behavior (such as in the event you are await()ing a download event), you will have to pass this option to launch():

    # Assuming $handle is a Playwright object
    my $browser = $handle->launch( type => 'firefox', firefoxUserPrefs => { 'pdfjs.disabled' => JSON::true } );

=head2 Leaving browsers alive for manual debugging

Passing the cleanup => 0 parameter to new() will prevent DESTROY() from cleaning up the playwright server when a playwright object goes out of scope.

Be aware that this will prevent debug => 1 from printing extra messages from playwright_server itself, as we redirect the output streams in this case so as not to fill your current session with prints later.

A convenience script has been provided to clean up these orphaned instances, `reap_playwright_servers` which will kill all extant `playwright_server` processes.

=head2 Taking videos, Making Downloads

We spawn browsers via BrowserType.launchServer() and then connect to them over websocket.
This means you can't just set paths up front and have videos recorded, the Video.path() method will throw.
Instead you will need to call the Video.saveAs() method after closing a page to record video:

    # Do stuff
    ...
    # Save video
    my $video = $page->video;
    $page->close();
    $video->saveAs('video/example.webm');

It's a similar story with Download classes:

    # Do stuff
    ...
    # Wait on Download
    my $promise = $page->waitForEvent('download')
    # Do some thing triggering a download
    ...

    my $download = $handle->await( $promise );
    $download->saveAs('somefile.extension');

Remember when doing an await() with playwright-perl you are waiting on a remote process on a server to complete, which can time out.
You may wish to spawn a subprocess using a different tool to download very large files.
If this is not an option, consider increasing the timeout on the LWP object used by the Playwright object (it's the 'ua' member of the class).

=head2 Doing arbitrary requests

When you either want to test APIs (or not look like a scraper/crawler) you'll want to issue arbitrary requests, such as POST/HEAD/DELETE et cetera.
Here's how you go about that:

    print "HEAD http://google.com : \n";
    my $fr = $page->request();
    my $resp = $fr->fetch("http://google.com", { method => "HEAD" });
    print Dumper($resp->headers());
    print "200 OK\n" if $resp->status() == 200;

The request() method will give you a Playwright::APIRequestContext object, which you can then call whichever methods you like upon.
When you call fetch (or get, post, etc) you will then be returned a Playwright::APIResponse object.

=head3 Differences in behavior from Selenium::Remote::Driver

By default selenium has its selector methods obeying a timeout and waits for an element to appear.
It then explodes when and element can't be found.

To replicate this mode of operation, we have provided the try_until helper:

    # Args are $object, $method, @args
    my $element = Playwright::try_until($page, 'select', $selector) or die ...;

This will use the timeouts described by pusht/popt (see below).

=head2 Perl equivalents for playwright-test

This section is intended to be read alongside the playwright-test documentation to aid understanding of common browser testing techniques.
The relevant documentation section will be linked for each section.

=head3 Annotations

L<https://playwright.dev/docs/test-annotations/>

Both L<Test::More> and L<Test2::V0> provide an equivalent to all the annotations but slow():

=over 4

=item B<skip or fixme> - Test::More::skip or Test2::Tools::Basic::skip handle both needs

=item B<fail> - Test::More TODO blocks and Test2::Tools::Basic::todo

=item B<slow> - Has no equivalent off the shelf.  Playwright::pusht() and Playwright::popt() are here to help.

    # Examples assume you have a $page object.

    # Timeouts are in milliseconds
    Playwright::pusht($page,5000);
    # Do various things...
    ...
    Playwright::popt($page);

See L<https://playwright.dev/docs/api/class-browsercontext#browser-context-set-default-timeout> for more on setting default timeouts in playwright.
By default we assume the timeout to be 30s.

=back

=head3 Assertions

As with before, most of the functionality here is satisfied with perl's default testing libraries.
In particular, like() and cmp_bag() will do most of what you want here.

=head3 Authentication

Much of the callback functionality used in these sections is provided by L<Test::Class> and it's fixtures.

=head3 Command Line

Both C<prove> and C<yath> have similar functionality, save for retrying flaky tests.
That said, you shouldn't do that; good tests don't flake.

=head3 Configuration

All the configuration here can simply be passed to launch(), newPage() or other methods directly.

=head3 Page Objects

This is basically what L<Test::Class> was written for specifically; so that you could subclass testing of common components across pages.

=head3 Parallelizing Tests

Look into L<Test::Class::Moose>'s Parallel runmode, C<prove>'s -j option, or L<Test2::Aggregate>.

=head3 Reporters

When using C<prove>, consider L<Test::Reporter> coupled with App::Prove::Plugins using custom TAP::Formatters.
Test2 as of this writing (October 2012) supports formatters and plugins, but no formatter plugins have been uploaded to CPAN.
See L<Test2::Manual::Tooling::Formatter> on writing a formatter yourself, and then a L<Test2::Plugin> using it.

=head3 Test Retry

C<prove> supports tests in sequence via the --rules option.
It's also got the handy --state options to further micromanage test execution over multiple iterations.
You can use this to retry flaking tests, but it's not a great idea in practice.

=head3 Visual Comparisons

Use L<Image::Compare>.

=head3 Advanced Configuration

This yet again can be handled when instantiating the various playwright objects.

=head3 Fixtures

L<Test::Class> and it's many variants cover the subject well.

=head1 INSTALLATION NOTE

If you install this module from CPAN, you will likely encounter a croak() telling you to install node module dependencies.
Follow the instructions and things should be just fine.

If you aren't, please file a bug!

=head1 CONSTRUCTOR

=head2 new(HASH) = (Playwright)

Creates a new browser and returns a handle to interact with it.

=head3 INPUT

    debug (BOOL) : Print extra messages from the Playwright server process. Default: false
    timeout (INTEGER) : Seconds to wait for the playwright server to spin up and down.  Default: 30s
    cleanup (BOOL) : Whether or not to clean up the playwright server when this object goes out of scope.  Default: true

=cut

our ( $spec, $server_bin, $node_bin, %mapper );

sub _check_node {

    # Check that node is installed
    $node_bin = File::Which::which('node');
    confess("node must exist, be in your PATH and executable") unless $node_bin && -x $node_bin;

    my $path2here = File::Basename::dirname( Cwd::abs_path( $INC{'Playwright.pm'} ) );

    # Make sure it's possible to start the server
    $server_bin = File::Which::which('playwright_server');
    confess("Can't locate playwright_server!
    Please ensure it is installed in your PATH.
    If you installed this module from CPAN, it should already be.")
      unless $server_bin && -x $server_bin;

    # Attempt to start the server.  If we can't do this, we almost certainly have dependency issues.
    my ($output) = capture_merged { system($node_bin, $server_bin, '--check') };
    return if $output =~ m/OK/;

    warn $output if $output;

    confess( "playwright_server could not run successfully.
    See the above error message for why.
    It's likely to be unmet dependencies, or a NODE_PATH issue.

    Install of node dependencies must be done manually.
    Run the following:

    npm i express playwright uuid
    sudo npx playwright install-deps
    export NODE_PATH=\"\$(pwd)/node_modules\".

    If you still experience issues, run the following:

    NODE_DEBUG=module playwright_server --check

    This should tell you why node can't find the deps you have installed.
    ");

}

sub _build_classes {
    foreach my $class ( keys(%$spec) ) {
        $mapper{$class} = sub {
            my ( $self, $res ) = @_;
            my $class = "Playwright::$class";
            return $class->new(
                handle => $self,
                id     => $res->{_guid},
                type   => $class,
                parent => $self,
            );
        };
    }
}

sub BEGIN {
    our $SKIP_BEGIN;
    _check_node() unless $SKIP_BEGIN;
}

sub new ( $class, %options ) {

    #XXX yes, this is a race, so we need retries in _start_server
    my $port = Net::EmptyPort::empty_port();
    my $timeout = $options{timeout} // 30;
    my $self = bless(
        {
            ua      => $options{ua} // LWP::UserAgent->new(),
            port    => $port,
            debug   => $options{debug},
            cleanup => $options{cleanup} // 1,
            pid     => _start_server( $port, $timeout, $options{debug}, $options{cleanup} // 1 ),
            parent  => $$,
            timeout => $timeout,
        },
        $class
    );

    $self->_check_and_build_spec();
    _build_classes();

    return $self;
}

sub _check_and_build_spec ($self) {
    return $spec if ref $spec eq 'HASH';

    $spec = Playwright::Util::request(
        'GET', 'spec', $self->{port}, $self->{ua},
    );

    confess("Could not retrieve Playwright specification.  Check that your playwright installation is correct and complete.") unless ref $spec eq 'HASH';
    return $spec;
}

=head1 METHODS

=head2 launch(HASH) = Playwright::Browser

The Argument hash here is essentially those you'd see from browserType.launch().  See:
L<https://playwright.dev/docs/api/class-browsertype#browsertypelaunchoptions>

There is an additional "special" argument, that of 'type', which is used to specify what type of browser to use, e.g. 'firefox'.

=cut

sub launch ( $self, %args ) {

    Playwright::Base::_coerce(
        $spec->{BrowserType}{members},
        args    => [ \%args ],
        command => 'launch'
    );
    delete $args{command};

    my $msg = Playwright::Util::request(
        'POST', 'session', $self->{port}, $self->{ua},
        type => delete $args{type},
        args => [ \%args ]
    );

    return $Playwright::mapper{ $msg->{_type} }->( $self, $msg )
      if ( ref $msg eq 'HASH' )
      && $msg->{_type}
      && exists $Playwright::mapper{ $msg->{_type} };
    return $msg;
}

=head2 server (HASH) = MIXED

Call Playwright::BrowserServer methods on the server which launched your browser object.

Parameters:

    browser : The Browser object you wish to call a server method upon.
    command : The BrowserServer method you wish to call

The most common use for this is to get the PID of the underlying browser process:

    my $browser = $playwright->launch( browser => chrome );
    my $process = $playwright->server( browser => $browser, command => 'process' );
    print "Browser process PID: $process->{pid}\n";

BrowserServer methods (at the time of writing) take no arguments, so they are not processed.

=cut

sub server ( $self, %args ) {
    return Playwright::Util::request(
        'POST', 'server', $self->{port}, $self->{ua},
        object  => $args{browser}{guid},
        command => $args{command},
    );
}

=head2 await (HASH) = Object

Waits for an asynchronous operation returned by the waitFor* methods to complete and returns the value.

=cut

sub await ( $self, $promise ) {
    my $obj = Playwright::Util::await($promise);

    return $obj unless $obj->{_type};
    my $class = "Playwright::$obj->{_type}";
    return $class->new(
        type   => $obj->{_type},
        id     => $obj->{_guid},
        handle => $self
    );
}

=head2 pusht(Playwright::Page, INTEGER timeout, BOOL navigation) = null

Like pushd/popd, but for default timeouts used by a Playwright::Page object and it's children.

If the 'navigation' option is high, we set the NavigationTimeout rather than the DefaultTimeout.
By default 'navigation' is false.

If we popt to the bottom of the stack, we will set the timeout back to 1 second.

=cut

sub pusht($object,$timeout, $navigation=0) {
    $object->{timeouts} //= [];
    push(@{$object->{timeouts}}, $timeout);
    return $object->setDefaultNavigationTimeout($timeout) if $navigation;
    return $object->setDefaultTimeout($timeout);
}

=head2 popt(Playwright::Page, BOOL navigation) = null

The counterpart to pusht() which returns the timeout value to it's previous value.

=cut

sub popt ($object, $navigation=0) {
    $object->{timeouts} //= [];
    my $last_timeout = pop(@{$object->{timeouts}}) // 1000;
    return $object->setDefaultNavigationTimeout($last_timeout) if $navigation;
    return $object->setDefaultTimeout($last_timeout);
}

=head2 try_until(Object, STRING method, LIST args), try_until_die(...)

Try to execute the provided method upon the provided Playwright::* object until it returns something truthy.
Quits after the timeout (or 1s, if pusht is not used before this) defined on the object is reached.

Use this for methods which *don't* support a timeout option, such as select().

=cut

sub try_until ($object, $method, @args) {
    my ($ctr, $result, $timeout) = (0);
    $timeout = $object->{timeouts}[-1] if ref $object->{timeouts} eq 'ARRAY';
    $timeout = $timeout / 1000 if $timeout;
    $timeout //= 1;
    while (!$result) {
        $result = $object->$method(@args);
        last if $result;
        sleep 1;
        $ctr++;
        last if $ctr >= $timeout;
    };
    return $result;
}

=head2 quit, DESTROY

Terminate the browser session and wait for the Playwright server to terminate.

Automatically called when the Playwright object goes out of scope.

=cut

sub quit ($self) {
    # Prevent double destroy after quit()
    return if $self->{killed};

    # Prevent destructor from firing in child processes so we can do things like async()
    # This should also prevent the waitpid below from deadlocking due to two processes waiting on the same pid.
    return unless $$ == $self->{parent};

    # Prevent destructor from firing in the event the caller instructs it to not fire
    return unless $self->{cleanup};

    # Make sure we don't mash the exit code of things like prove
    local $?;

    $self->{killed} = 1;
    print "Attempting to terminate server process...\n" if $self->{debug};
    Playwright::Util::request( 'GET', 'shutdown', $self->{port}, $self->{ua} );

    # 0 is always WCONTINUED, 1 is always WNOHANG, and POSIX is an expensive import
    # When 0 is returned, the process is still active, so it needs more persuasion
    foreach (0..3) {
        return unless waitpid( $self->{pid}, 1) == 0;
        sleep 1;
    }

    # Advanced persuasion
    print "Forcibly terminating server process...\n" if $self->{debug};
    kill('TERM', $self->{pid});

    #XXX unfortunately I can't just do a SIGALRM, because blocking system calls can't be intercepted on win32
    foreach (0..$self->{timeout}) {
        return unless waitpid( $self->{pid}, 1 ) == 0;
        sleep 1;
    }
    warn "Could not shut down playwright server!";
    return;
}

sub DESTROY ($self) {
    $self->quit();
}

sub _start_server ( $port, $timeout, $debug, $cleanup ) {
    $debug = $debug ? '--debug' : '';

    $ENV{DEBUG} = 'pw:api' if $debug;
    my $pid = fork // confess("Could not fork");
    if ($pid) {
        print "Waiting for port to come up...\n" if $debug;
        Net::EmptyPort::wait_port( $port, $timeout )
          or confess("Server never came up after 30s!");
        print "done\n" if $debug;

        return $pid;
    }

    # Orphan the process in the event that cleanup => 0
    if (!$cleanup) {
        print "Detaching child process...\n";
        chdir '/';
        require POSIX;
        die "Cannot detach playwright_server process for persistence" if POSIX::setsid() < 0;
        require Capture::Tiny;
        capture_merged { exec( $node_bin, $server_bin, "--port", $port, $debug ) };
        die("Could not exec!");
    }
    exec( $node_bin, $server_bin, "--port", $port, $debug );
}

1;
