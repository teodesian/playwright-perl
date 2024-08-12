use feature ':5.16';

use strict;
use warnings;

use Cwd 'abs_path';
use FindBin;
use Playwright;
use Playwright::Util;
use Test2::V0;

BEGIN {
    unless ($ENV{AUTHOR_TESTING}) {
        print qq{1..0 # SKIP these tests are for testing by the author\n};
        exit;
    }
    $ENV{NODE_PATH} //= '';
    $ENV{NODE_PATH} = Playwright::Util::find_node_modules().":$ENV{NODE_PATH}";
}

my $handle = Playwright->new();
my $browser = $handle->launch( headless => 1, type => 'chrome' );
my $page = $browser->newPage();

my $page_file = Playwright::Util::_find( "js_dialog.html" );
my $res = $page->goto( "file://$page_file", { waitUntil => 'networkidle' });

# Test that we can confirm a javascript dialog via JS
$page->on( 'dialog', 'dialog', qq|dialog.accept();| );
my $promise = $page->waitForEvent( 'dialog' );
$page->locator( '[type="submit"]' )->click();
my $dlg = $handle->await($promise);

like( $dlg->message(), qr/Are you sure/, "Dialog message" );

like( $page->locator( '#result')->innerText(), qr/submitted/, "Form was submitted" );

done_testing();

