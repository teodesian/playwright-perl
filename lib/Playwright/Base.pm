package Playwright::Base;

use strict;
use warnings;

use Sub::Install();

use Async;
use JSON;
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

sub _coerce($spec,%args) {
    #Coerce bools correctly
    my @argspec = values(%{$spec->{$args{command}}{args}});
    @argspec = sort { $a->{order} <=> $b->{order} } @argspec;

    for (my $i=0; $i < scalar(@argspec); $i++) {
        next unless $i < @{$args{args}};
        my $arg = $args{args}[$i];
        my $type = $argspec[$i]->{type};
        if ($type->{name} eq 'boolean') {
            my $truthy = int(!!$arg);
            $args{args}[$i] = $truthy ? JSON::true : JSON::false;
        } elsif ($type->{name} eq 'Object' ) {
            foreach my $prop (keys(%{$type->{properties}})) {
                next unless exists $arg->{$prop};
                my $truthy = int(!!$arg->{$prop});
                next unless $type->{properties}{$prop}{type}{name} eq 'boolean';
                $args{args}[$i]->{$prop} = $truthy ? JSON::true : JSON::false;
            }
        }
    }

    return %args;
}

sub _request ($self, %args) {

    %args = Playwright::Base::_coerce($self->{spec},%args);

    return AsyncData->new( sub { &Playwright::Base::_do($self, %args) }) if $args{command} =~ m/^waitFor/;

    my $msg = Playwright::Base::_do->($self,%args);

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
