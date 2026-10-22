use strict;
use warnings;

use Test2::V0;
use lib 'xt/lib';
use Playwright::AuthorTest;
use Playwright;

# 1x1 PNG, 67 bytes, plenty of which are not valid UTF-8
my $png = pack 'H*', '89504e470d0a1a0a0000000d4948445200000001000000010806000000'
    . '1f15c4890000000d49444154789c6300010000050001'
    . '0d0a2db40000000049454e44ae426082';

my $handle = Playwright->new( debug => 1 );
my $page   = $handle->launch( headless => 1, type => 'chrome' )->newPage;
$page->setContent('<input type="file" id="f" multiple>');

my $payload = { name => 'a.png', mimeType => 'image/png', buffer => $png };
$page->setInputFiles( '#f', $payload );
is( $page->evaluate('return document.querySelector("#f").files[0].size'), length $png, "setInputFiles with a buffer payload uploads every byte" );

$page->setInputFiles( '#f', [ $payload, { %$payload, name => 'b.png' } ] );
is( $page->evaluate('return document.querySelector("#f").files.length'), 2, "setInputFiles with a list of buffer payloads uploads them all" );

# Read the bytes back in the browser to show they were not mangled in transit
my $hex = $page->evaluate(q{
    return document.querySelector("#f").files[0].arrayBuffer().then(
        b => Array.from(new Uint8Array(b)).map(x => x.toString(16).padStart(2, '0')).join('')
    );
});
is( $hex, unpack( 'H*', $png ), "Uploaded bytes match the ones we sent" );

$handle->quit;

done_testing();
