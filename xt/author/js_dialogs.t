use feature ':5.16';

use strict;
use warnings;
use utf8;
use open ':std', OUT => ':encoding(UTF-8)';

BEGIN {
   unless ($ENV{AUTHOR_TESTING}) {
     print qq{1..0 # SKIP these tests are for testing by the author\n};
     exit;
    }
   $ENV{PATH} = "./bin:$ENV{PATH}";
}

use Cwd 'abs_path';
use Playwright;
use Test2::V0;

my $handle = Playwright->new();
my $browser = $handle->launch( headless => 0, type => 'chrome' );
my $page = $browser->newPage();
my $frameset = $page->mainFrame();
my $kidframes = $frameset->childFrames();

my $page_file = abs_path( 't/at/js_dialog.html' );
my $res = $page->goto( "file://$page_file", { waitUntil => 'networkidle' });

# Test that the console works

my $async = $page->waitForEvent('console');
# The console is race-y on my macbook
sleep 1;
$page->evaluate('console.log("whee")');
my $console = $handle->await( $async );
ok( $console->text(), 'whee', "Console log message" );

# Test that we can confirm a javascript dialog

$page->on( 'dialog', 'dialog', qq|dialog.accept();| );
my $promise = $page->waitForEvent( 'dialog' );
$page->locator( '[type="submit"]' )->click();
my $dlg = $handle->await($promise);

like( $dlg->message(), qr/Are you sure/, "Dialog message" );

like( $page->locator( '#result')->innerText(), qr/submitted/, "Form was submitted" );

done_testing();

