package Playwright::Base;

use strict;
use warnings;

use Sub::Install();

use Async;
use Playwright::Util();

#ABSTRACT: Object representing Playwright pages

no warnings 'experimental';
use feature qw{signatures};

=head2 DESCRIPTION

Base class for each Playwright class magic'd up by Sub::Install in Playwright's BEGIN block.
You probably shouldn't use this.

The specification for each class can be inspected with the 'spec' property:

    use Data::Dumper;
    my $object = Playwright::Base->new(...);
    print Dumper($object->{spec});

=head1 CONSTRUCTOR

=head2 new(HASH) = (Playwright::Base)

Creates a new page and returns a handle to interact with it.

=head3 INPUT

    handle (Playwright) : Playwright object.
    id (STRING)         : _guid returned by a response from the Playwright server with the provided type.
    type (STRING)       : Type to actually use

=cut

sub AUTOLOAD {
    our $AUTOLOAD;
    my $method = $AUTOLOAD;
    my ($self,@args) = @_;

    return Playwright::Base::_request($self, args => [@args], command => $method, object => $self->{guid}, type => $self->{type} );
}

sub new ($class, %options) {

    my $self = bless({
        spec    => $Playwright::spec->{$options{type}}{members},
        type    => $options{type},
        guid    => $options{id},
        ua      => $options{handle}{ua},
        port    => $options{handle}{port},
    }, $class);

    return ($self);
}

sub _request ($self, %args) {
    return AsyncData->new( sub { &Playwright::Base::_do($self, %args) }) if $args{command} =~ m/^waitFor/;

    my $msg = Playwright::Base::_do->($self,%args);

    use Data::Dumper;
    print Dumper($msg);

    if (ref $msg eq 'ARRAY') {
        @$msg = map {
            my $subject = $_;
            $subject = $Playwright::mapper{$_->{_type}}->($self,$_) if (ref $_ eq 'HASH') && $_->{_type} && exists $Playwright::mapper{$_->{_type}};
            $subject
        } @$msg;
    }
    return $Playwright::mapper{$msg->{_type}}->($self,$msg) if (ref $msg eq 'HASH') && $msg->{_type} && exists $Playwright::mapper{$msg->{_type}};
    return $msg;
}

sub _do ($self, %args) {
    return Playwright::Util::request ('POST', 'command', $self->{port}, $self->{ua}, %args);
}

1;
