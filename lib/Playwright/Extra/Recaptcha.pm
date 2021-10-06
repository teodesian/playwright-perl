package Playwright::Extra::Recaptcha;

#ABSTRACT: Load @extra/recaptcha playwright plugin, and expose the solveRecaptchas() method to Playwright::Page objects.

use strict;
use warnings;

use Sub::Install;

use parent qw{Playwright::Extra};

=head1 SYNOPSIS

    use Playwright;
    use Playwright::Extra::Recaptcha;
    Playwright::Extra::Humanize->setup($API_KEY);
    ...
    $page->solveRecaptchas();
    ...

=cut

sub setup {
    my ($class,$key) = @_;
    Sub::Install::install_sub({
        code => sub {
            my $self = shift;
            return $self->_api_request(
                args    => [@_],
                command => 'solveRecaptchas',
                object  => $self->{guid},
                type    => $self->{type}
            );
        },
        into => 'Playwright::Page',
        as   => 'solveRecaptchas'
    });
    my $payload = qq~
        if (debug) {
            console.log('Loading ReCaptcha plugin...');
        }
        const RecaptchaPlugin = require('\@extra/recaptcha');

        if (typeof extras_setup === 'undefined') {
            for (var br in browsers) {
                console.log('fix', br);
                browsers[br] = require('playwright-extra');
            }
        }

        const RecaptchaOptions = {
            visualFeedback: true, // colorize reCAPTCHAs (violet = detected, green = solved)
            provider: {
                id: '2captcha',
                token: '$key',
            }
        };
        for (var br in browsers) {
            browsers[br].use(
                RecaptchaPlugin(RecaptchaOptions)
            );
        }

        // Make sure the spec validator doesn't catch us
        spec.Page.members.push('solveRecaptchas');

        var extras_setup = 1;
        if (debug) {
            console.log('Done loading ReCaptcha plugin!');
        }
    ~;
    $class->SUPER::setup($payload);
}

1;
