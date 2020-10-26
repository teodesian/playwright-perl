package Playwright;

use strict;
use warnings;

use sigtrap qw/die normal-signals/;

use File::Basename();
use Cwd();
use LWP::UserAgent();
use Sub::Install();
use Net::EmptyPort();
use JSON::MaybeXS();
use File::Slurper();
use Carp qw{confess};

use Playwright::Base();
use Playwright::Util();

#ABSTRACT: Perl client for Playwright

no warnings 'experimental';
use feature qw{signatures state};

=head2 SYNOPSIS

    use JSON::PP;
    use Playwright;

    my $handle = Playwright->new();
    my $browser = $handle->launch( headless => JSON::PP::false, type => 'chrome' );
    my $page = $browser->newPage();
    my $res = $page->goto('http://google.com', { waitUntil => 'networkidle' });
    my $frameset = $page->mainFrame();
    my $kidframes = $frameset->childFrames();

=head2 DESCRIPTION

Perl interface to a lightweight node.js webserver that proxies commands runnable by Playwright.
Currently understands commands you can send to all the playwright classes defined in api.json.

See L<https://playwright.dev/#version=master&path=docs%2Fapi.md&q=>
for what the classes do, and their usage.

There is one major exception in how things work versus the documentation.
The selector functions have to be renamed from starting with $ for obvious reasons.
The renamed functions are as follows:

=over 4

=item $ => select

=item $$ => selectMulti

=item $eval => eval

=item $$eval => evalMulti

=back

These functions are present as part of the Page, Frame and ElementHandle classes.

=head1 CONSTRUCTOR

=head2 new(HASH) = (Playwright)

Creates a new browser and returns a handle to interact with it.

=head3 INPUT

    debug (BOOL) : Print extra messages from the Playwright server process

=cut

our ($spec, $server_bin, %mapper);

BEGIN {
    my $path2here = File::Basename::dirname(Cwd::abs_path($INC{'Playwright.pm'}));
    my $specfile = "$path2here/../api.json";
    confess("Can't locate Playwright specification in '$specfile'!") unless -f $specfile;

    my $spec_raw = File::Slurper::read_text($specfile);
    my $decoder = JSON::MaybeXS->new();
    $spec = $decoder->decode($spec_raw);

    foreach my $class (keys(%$spec)) {
        $mapper{$class} = sub {
            my ($self, $res) = @_;
            my $class = "Playwright::$class";
            return $class->new( handle => $self, id => $res->{_guid}, type => $class );
        };

        #All of the Playwright::* Classes are made by this MAGIC
        Sub::Install::install_sub({
            code => sub ($classname,%options) {
                @class::ISA = qw{Playwright::Base};
                $options{type} = $class;
                return Playwright::Base::new($classname,%options);
            },
            as   => 'new',
            into => "Playwright::$class",
        });
    }

    # Make sure it's possible to start the server
    $server_bin = "$path2here/../bin/playwright.js";
    confess("Can't locate Playwright server in '$server_bin'!") unless -f $specfile;
}

sub new ($class, %options) {

    #XXX yes, this is a race, so we need retries in _start_server
    my $port = Net::EmptyPort::empty_port();
    my $self = bless({
        ua      => $options{ua} // LWP::UserAgent->new(),
        port    => $port,
        debug   => $options{debug},
        pid     => _start_server( $port, $options{debug}),
    }, $class);

    return $self;
}

=head1 METHODS

=head2 launch(HASH) = Playwright::Browser

The Argument hash here is essentially those you'd see from browserType.launch().  See:
L<https://playwright.dev/#version=v1.5.1&path=docs%2Fapi.md&q=browsertypelaunchoptions>

There is an additional "special" argument, that of 'type', which is used to specify what type of browser to use, e.g. 'firefox'.

=cut

sub launch ($self, %args) {
    #TODO coerce types based on spec
    my $msg = Playwright::Util::request ('POST', 'session', $self->{port}, $self->{ua}, type => delete $args{type}, args => [\%args] );
    return $Playwright::mapper{$msg->{_type}}->($self,$msg) if (ref $msg eq 'HASH') && $msg->{_type} && exists $Playwright::mapper{$msg->{_type}};
    return $msg;
}

=head2 quit, DESTROY

Terminate the browser session and wait for the Playwright server to terminate.

Automatically called when the Playwright object goes out of scope.

=cut

sub quit ($self) {
    Playwright::Util::request ('GET', 'shutdown', $self->{port}, $self->{ua} ); 
    return waitpid($self->{pid},0);
}

sub DESTROY ($self) {
    $self->quit();
}

sub _start_server($port, $debug) {
    $debug   = $debug   ? '-d' : '';

    $ENV{DEBUG} = 'pw:api';
    my $pid = fork // confess("Could not fork");
    if ($pid) {
        print "Waiting for port to come up..." if $debug;
        Net::EmptyPort::wait_port($port,30) or confess("Server never came up after 30s!");
        print "done\n" if $debug;
        return $pid;
    }

    exec( $server_bin, "-p", $port, $debug);
}

1;
