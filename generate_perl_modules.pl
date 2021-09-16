#!/usr/bin/perl

# The point of this is to build skeleton classes which are then fleshed out at runtime
# so that people can wrap a mop around it

use strict;
use warnings;

use FindBin;
use File::Slurper;
use JSON;

use lib "$FindBin::Bin/lib";
use Playwright::Util;

my $module_source = '';
while (<DATA>) {
    $module_source .= $_;
}

# Next, grab the API JSON and iterate to build classes.
our $raw = File::Slurper::read_binary("$FindBin::Bin/api.json");
our $spec = JSON::decode_json($raw);
$spec = Playwright::Util::arr2hash($spec,'name');

our %mapper = (
    mouse     =>  "
=head2 mouse()

Returns a Playwright::Mouse object.

=cut

sub mouse {
    my ( \$self ) = \@_;
    return Playwright::Mouse->new(
        handle => \$self,
        parent => \$self,
        id     => \$self->{guid},
    );
}\n\n",
    keyboard => "
=head2 keyboard()

Returns a Playwright::Keyboard object.

=cut

sub keyboard {
    my ( \$self ) = \@_;
    return Playwright::Keyboard->new(
        handle => \$self,
        parent => \$self,
        id     => \$self->{guid},
    );
}\n\n",
);

our %methods_to_rename = (
    '$'                 => 'select',
    '$$'                => 'selectMulti',
    '$eval'             => 'eval',
    '$$eval'            => 'evalMulti',
);

our %bogus_methods = (
    'querySelector'     => '$',
    'querySelectorAll'  => '$$',
    'evalOnSelector'    => '$eval',
    'evalOnSelectorAll' => '$$eval',
);

# Playwright methods we can't actually have work here
our @banned = ('_request');

my @modules;
foreach my $class ( keys(%$spec), 'Mouse', 'Keyboard' ) {
    next if $class eq 'Playwright';
    my $pkg = "Playwright::$class";
    my $subs = '';
    push(@modules,$pkg);
    my @seen;

    my $members = Playwright::Util::arr2hash($spec->{$class}{members},'name');
    foreach my $method ( ( keys( %$members ), 'on', 'evaluate', 'evaluateHandle' ) ) {
        next if grep { $_ eq $method } @banned;
        my $renamed = $method;
        $method  = $bogus_methods{$method}     if exists $bogus_methods{$method};
        $renamed = $methods_to_rename{$method} if exists $methods_to_rename{$method};
        next if grep { $method eq $_ } @seen;
        if (exists $mapper{$method}) {
            $subs .= $mapper{$method};
        } else {
            $subs .= "
=head2 $renamed\(\@args)

Execute the $class\:\:$renamed playwright routine.

See L<https://playwright.dev/api/class-$class#$class-$method> for more information.

=cut

sub $renamed {
    my \$self = shift;
    return \$self->_request(
        args    => [\@_],
        command => '$method',
        object  => \$self->{guid},
        type    => \$self->{type}
    );
}\n\n";
        }
        push(@seen,$method);
    }
    my $local_source = $module_source;
    $local_source =~ s/\%REPLACEME\%/$pkg/gm;
    $local_source =~ s/\%CLASSNAME\%/$class/gm;
    $local_source =~ s/\%SUBROUTINES\%/$subs/gm;
    open(my $fh, '>', "$FindBin::Bin/lib/Playwright/$class.pm");
    print $fh $local_source;
    close $fh;
}

# Now overwrite the list of modules in Playwright.pm
open(my $fh, '>', "$FindBin::Bin/lib/Playwright/ModuleList.pm");
print $fh "#ABSTRACT: Playwright sub classes.
#PODNAME: Playwright::ModuleList
# You should not use this directly; use Playwright instead.

package Playwright::ModuleList;

use strict;
use warnings;

";

foreach my $mod (@modules) {
    print $fh "use $mod;\n";
}

print $fh "\n1;\n";
close($fh);

1;

__DATA__
# ABSTRACT: Automatically generated class for %REPLACEME%
# PODNAME: %REPLACEME%

# These classes used to be generated at runtime, but are now generated when the module is built.
# Don't send patches against these modules, they will be ignored.
# See generate_perl_modules.pl in the repository for generating this.

use strict;
use warnings;

package %REPLACEME%;

use parent 'Playwright::Base';

=head1 CONSTRUCTOR

=head2 new(%options)

You shouldn't have to call this directly.
Instead it should be returned to you as the result of calls on Playwright objects, or objects it returns.

=cut

sub new {
    my ($self,%options) = @_;
    $options{type} = '%CLASSNAME%';
    return $self->SUPER::new(%options);
}

=head1 METHODS

=cut

%SUBROUTINES%

1;
