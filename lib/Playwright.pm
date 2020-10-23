package Playwright;

use strict;
use warnings;

use sigtrap qw/die normal-signals/;

use File::Basename();
use Cwd();
use Net::EmptyPort();
use LWP::UserAgent();
use Sub::Install();
use JSON::MaybeXS();
use File::Slurper();
use Carp qw{confess};

use Playwright::Page();

#ABSTRACT: Perl client for Playwright

no warnings 'experimental';
use feature qw{signatures state};

=head2 SYNOPSIS

    use Playwright;
    my ($browser,$page) = Playwright->new( browser => "chrome" );
    $page->goto('http://www.google.com');
    my $browser_version = $browser->version();
    $browser->quit();

=head2 DESCRIPTION

Perl interface to a lightweight node.js webserver that proxies commands runnable by Playwright.
Currently understands commands you can send to the following Playwright classes,
commands for which can be sent via instances of the noted module

=over 4

=item B<Browser> - L<Playwright> L<https://playwright.dev/#version=master&path=docs%2Fapi.md&q=class-browser>

=item B<BrowserContext> - L<Playwright> L<https://playwright.dev/#version=master&path=docs%2Fapi.md&q=class-browsercontext>

=item B<Page> - L<Playwright::Page> L<https://playwright.dev/#version=v1.5.1&path=docs%2Fapi.md&q=class-page>

=item B<Response> - L<Playwright::Response> L<https://playwright.dev/#version=v1.5.1&path=docs%2Fapi.md&q=class-response>

=back

The specification for the above classes can also be inspected with the 'spec' method for each respective class:

    use Data::Dumper;
    print Dumper($browser->spec , $page->spec, ...);

=head1 CONSTRUCTOR

=head2 new(HASH) = (Playwright)

Creates a new browser and returns a handle to interact with it.

=head3 INPUT

    browser (STRING) : Name of the browser to use.  One of (chrome, firefox, webkit).
    visible (BOOL)   : Whether to start the browser such that it displays on your desktop (headless or not).
    debug   (BOOL)   : Print extra messages from the Playwright server process

=cut

our ($spec, $server_bin, %class_spec);

my %transmogrify = (
    Page   => sub { 
        my ($self, $res) = @_;
        require Playwright::Page;
        return Playwright::Page->new( browser => $self, id => $res->{_guid} );
    },
);

BEGIN {
    my $path2here = File::Basename::dirname(Cwd::abs_path($INC{'Playwright.pm'}));
    my $specfile = "$path2here/../api.json";
    confess("Can't locate Playwright specification in '$specfile'!") unless -f $specfile;

    my $spec_raw = File::Slurper::read_text($specfile);
    my $decoder = JSON::MaybeXS->new();
    $spec = $decoder->decode($spec_raw);
    %class_spec = (
        %{$spec->{Browser}{members}},
        %{$spec->{BrowserContext}{members}}
    );

    # Install the subroutines if they aren't already
    foreach my $method (keys(%class_spec)) {
        Sub::Install::install_sub({
            code => sub { _request(shift, \%transmogrify, args => [@_], command => $method, type => 'Browser', object => 'browser' ) },
            as   => $method,
        });
    }

    # Make sure it's possible to start the server
    $server_bin = "$path2here/../bin/playwright.js";
    confess("Can't locate Playwright server in '$server_bin'!") unless -f $specfile;
    1;
}

sub new ($class, %options) {

    #XXX yes, this is a race, so we need retries in _start_server
    my $port = Net::EmptyPort::empty_port();
    my $self = bless({
        spec    => $spec,
        ua      => $options{ua} // LWP::UserAgent->new(),
        browser => $options{browser},
        visible => $options{visible},
        port    => $port,
        debug   => $options{debug},
        pid     => _start_server($options{browser},$options{visible}, $port, $options{debug}),
    }, $class);

    $self->_request( \%transmogrify, url => 'session' );
    return $self;
}

=head1 METHODS

=head2 spec

Return the relevant methods and their definitions for this module which are built dynamically from the Playwright API spec.

=cut

sub spec ($self) {
    return %class_spec;
}

=head2 quit, DESTROY

Terminate the browser session and wait for the Playwright server to terminate.

Automatically called when the Playwright object goes out of scope.

=cut

sub quit ($self) {
    $self->_request( \%transmogrify, url => 'shutdown' );
    return waitpid($self->{pid},0);
}

sub DESTROY ($self) {
    $self->quit();
}

sub _start_server($browser,$visible, $port, $debug) {
    confess("Invalid browser '$browser'") unless grep { $_ eq $browser } qw{chrome firefox webkit};
    $visible = $visible ? '-v' : '';
    $debug   = $debug   ? '-d' : '';

    $ENV{DEBUG} = 'pw:api';
    my $pid = fork // confess("Could not fork");
    if ($pid) {
        print "Waiting for port to come up..." if $debug;
        Net::EmptyPort::wait_port($port,30) or confess("Server never came up after 30s!");
        print "done\n" if $debug;
        return $pid;
    }

    exec( $server_bin, $browser, $visible, "-p", $port, $debug);
}

sub _request ($self, $translator, %args) {
    $translator //= \%transmogrify;
    my $url = $args{url} // 'command';
    my $fullurl = "http://localhost:$self->{port}/$url";

    my $method = $url eq 'command' ? 'POST' : 'GET';

    my $request  = HTTP::Request->new( $method, $fullurl);
    $request->header( 'Content-type' => 'application/json' );
    $request->content( JSON::MaybeXS::encode_json(\%args) );
    my $response = $self->{ua}->request($request);
    my $decoded  = JSON::MaybeXS::decode_json($response->decoded_content());
    my $msg = $decoded->{message};

    confess($msg) if $decoded->{error};

    return $translator->{$msg->{_type}}->($self,$msg) if (ref $msg eq 'HASH') && $msg->{_type} && exists $translator->{$msg->{_type}};
    return $msg;
}

1;
