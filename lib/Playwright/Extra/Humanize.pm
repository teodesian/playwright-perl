package Playwright::Extra::Humanize;

#ABSTRACT: Loads the @extra/humanize playwright plugin from playwright-extras

use strict;
use warnings;

use parent qw{Playwright::Extra};

=head1 SYNOPSIS

    use Playwright;
    use Playwright::Extra::Humanize;
    Playwright::Extra::Humanize->setup();
    ...

=cut

my $payload = qq{
    if (debug) {
        console.log('Loading Humanize plugin...');
    }
    const HumanizePlugin = require('\@extra/humanize');

    if (typeof extras_setup === 'undefined') {
        for (var br in browsers) {
            console.log('fix', br);
            browsers[br] = require('playwright-extra');
        }
    }
    for (var br in browsers) {
        browsers[br].use(
            HumanizePlugin(
                mouse : {
                    showCursor: true
                }
            )
        );
    }
    var extras_setup = 1;
    if (debug) {
        console.log('Done loading Humanize plugin!');
    }
};

sub setup {
    my $class = shift;
    $class->SUPER::setup($payload);
}

1;
