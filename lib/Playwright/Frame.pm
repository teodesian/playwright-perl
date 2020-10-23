package Playwright::Frame;

use strict;
use warnings;

use Sub::Install();
use Carp qw{confess};

#ABSTRACT: Object representing Playwright pages

no warnings 'experimental';
use feature qw{signatures state};

=head2 SYNOPSIS

    use Playwright;
    my ($browser,$page) = Playwright->new( browser => "chrome" );
    $page->goto('http://www.google.com');
    my $browser_version = $browser->version();
    $browser->quit();

=head2 DESCRIPTION

Perl interface to a lightweight node.js webserver that proxies commands runnable by Playwright in the 'Frame' Class.
See L<https://playwright.dev/#version=master&path=docs%2Fapi.md&q=class-frame> for more information.

The specification for this class can also be inspected with the 'spec' method:

    use Data::Dumper;
    my $page = Playwright::Page->new(...);
    print Dumper($page->spec);

=head1 CONSTRUCTOR

=head2 new(HASH) = (Playwright::Frame)

Creates a new page and returns a handle to interact with it, along with a Playwright::Frame (the main Frame) to interact with (supposing the page is a FrameSet).

=head3 INPUT

    browser (Playwright) : Playwright object.
    page (STRING) : _guid returned by a response from the Playwright server with _type of 'Page'.

=cut

my %transmogrify = (
    Frame         => sub {
        my ($self, $res) = @_;
        require Playwright::Frame;
        return Playwright::Frame->new( browser => $self, id => $res->{_guid} );
    },
    ElementHandle => sub {
        my ($self, $res) = @_;
        require Playwright::Element;
        return Playwright::Element->new( browser => $self, id    => $res->{_guid} ); 
    },
    Response => sub {
        my ($self, $res) = @_;
        require Playwright::Response;
        return Playwright::Response->new( browser => $self, id   => $res->{_guid} );
    },
);

sub new ($class, %options) {

    my $self = bless({
        spec    => $options{browser}{spec}{Frame}{members},
        browser => $options{browser},
        guid    => $options{id},
    }, $class);

    # Install the subroutines if they aren't already
    foreach my $method (keys(%{$self->{spec}})) {
        Sub::Install::install_sub({
            code => sub {
                my $self = shift;
                $self->{browser}->_request( \%transmogrify, args => [@_], command => $method, object => $self->{guid}, type => 'Frame' )
            },
            as   => $method,
        }) unless $self->can($method);
    }

    return ($self);
}

=head1 METHODS

=head2 spec

Return the relevant methods and their definitions for this module which are built dynamically from the Playwright API spec.

=cut

sub spec ($self) {
    return %{$self->{spec}};
}

1;
