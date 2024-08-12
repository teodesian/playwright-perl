use strict;
use warnings;

use Test2::V0;
use Test2::Tools::Explain;
use Playwright;

BEGIN {
   unless ($ENV{AUTHOR_TESTING}) {
     print qq{1..0 # SKIP these tests are for testing by the author\n};
     exit;
    }
}

my $handle  = Playwright->new( debug => 1 );
my $handle2 = Playwright->new( debug => 1, host => 'localhost', port => $handle->{port} );

my $browser = $handle->launch( headless => 1, type => 'firefox' );
my $process = $handle->server( browser => $browser, command => 'process' );

my $browser2 = $handle2->launch( headless => 1, type => 'firefox' );
my $process2 = $handle2->server( browser => $browser, command => 'process' );
is($process->{pid}, $process2->{pid}, "Same process in both playwright instances");

done_testing();
