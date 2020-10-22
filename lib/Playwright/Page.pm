package Playwright::Page;

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

Perl interface to a lightweight node.js webserver that proxies commands runnable by Playwright in the 'Page' Class.
See L<https://playwright.dev/#version=v1.5.1&path=docs%2Fapi.md&q=class-page> for more information.

The specification for this class can also be inspected with the 'spec' method:

    use Data::Dumper;
    my $page = Playwright::Page->new(...);
    print Dumper($page->spec);

=head1 CONSTRUCTOR

=head2 new(HASH) = (Playwright,Playwright::Frame)

Creates a new page and returns a handle to interact with it, along with a Playwright::Frame (the main Frame) to interact with (supposing the page is a FrameSet).

=head3 INPUT

    browser (Playwright) : Playwright object.
    page (STRING) : _guid returned by a response from the Playwright server with _type of 'Page'.

=cut

sub new ($class, %options) {

    my $self = bless({
        spec    => $options{browser}{spec}{Page}{members},
        browser => $options{browser},
        guid    => $options{page},
    }, $class);

    # Install the subroutines if they aren't already
    foreach my $method (keys(%{$self->{spec}})) {
        Sub::Install::install_sub({
            code => sub { _request(@_) },
            as   => $method,
        }) unless $self->can($method);
    }

    return ($self);#, $self->mainFrame());
}

=head1 METHODS

=head2 spec

Return the relevant methods and their definitions for this module which are built dynamically from the Playwright API spec.

=cut

sub spec ($self) {
    return %{$self->{spec}};
}

my %transmogrify = (
    Frame         => sub {
        my ($self, $res) = @_;
        require Playwright::Frame;
        return Playwright::Frame->new(   page => $self, frame => $res->{_guid} );
    },
    ElementHandle => sub {
        my ($self, $res) = @_;
        require Playwright::Element;
        return Playwright::Element->new( page => $self, id    => $res->{_guid} ); 
    },
);

sub _request ($self,%options) {
    $options{page} = $self->{guid};
    return $self->SUPER::_request(%options);
}

1;
