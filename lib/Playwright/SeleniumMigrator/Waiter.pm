package Selenium::Waiter;

use strict;
use warnings;

use v5.28;

use base 'Exporter';
use Carp qw{confess};

no warnings 'experimental';
use feature qw{signatures};

our @EXPORT_OK = ('wait_until');

sub wait_until :prototype(&;@) ($code, %opts) {
    my $timeout  = $opts{timeout}  // 30;   # seconds (Selenium::Waiter default)
    my $interval = $opts{interval} // 0.5;  # seconds
    my $die      = $opts{die}      // 0;
    my $debug    = $opts{debug}    // 0;

    my $start = time();
    while (1) {
        my $result = eval { $code->() };
        my $err = $@;

        if ($result) {
            return $result;
        }

        if ($debug && $err) {
            warn "wait_until caught: $err\n";
        }

        my $elapsed = time() - $start;
        if ($elapsed >= $timeout) {
            if ($die) {
                confess "Timed out after ${timeout}s in wait_until";
            }
            return 0;
        }

        select(undef, undef, undef, $interval);
    }
}

1;
