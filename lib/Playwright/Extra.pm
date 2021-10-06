package Playwright::Extra;

#ABSTRACT: Base class for playwright extension modules

use strict;
use warnings;

use Playwright;

=head1 SYNOPSIS

    package Playwright::Extra::Subclass;

    use strict;
    use warnings;

    use parent qw{Playwright::Extra};

    # This is javascript
    my $payload = qq{
        if (debug) {
            console.log('Loading plugin...');
        }
        // Add your code here
        if (debug) {
            console.log('Done loading plugin!');
        }
    };

    sub setup {
        my $class = shift;
        # Use Sub::Install here if we need to extend other classes to call new playwright methods
        $class->SUPER::setup($payload);
    }

    1;

=cut

sub setup {
    my ($class,$payload) = @_;
    push(@{$Playwright::EXTRAS}, $payload);
    return 1;
}

1;
