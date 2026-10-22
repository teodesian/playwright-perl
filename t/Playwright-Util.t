use Test2::V0 -target => 'Playwright::Util';
use Test2::Tools::Explain;
use Playwright::Util;
use Test::MockModule qw{strict};

my $lwpmock = Test::MockModule->new('LWP::UserAgent');
$lwpmock->redefine('request', sub {
    return bless({},'BogusResponse');
});

no warnings qw{redefine once};
my $json = '{ "error":true, "message":"waa"}';
local *BogusResponse::decoded_content = sub {
    return $json;
};
use warnings;

like( dies { Playwright::Util::request('tickle','chase', 'localhost', 666, LWP::UserAgent->new(), a => 'b' ) }, qr/waa/i, "Bad response from server = BOOM");

$json = q[<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>Error</title>
</head>
<body>
<pre>PayloadTooLargeError: request entity too large<br> &nbsp; &nbsp;at readStream (/ms-playwright-agent/node_modules/raw-body/index.js:163:17)<br> &nbsp; &nbsp;at getRawBody (/ms-playwright-agent/node_modules/raw-body/index.js:116:12)<br> &nbsp; &nbsp;at read (/ms-playwright-agent/node_modules/body-parser/lib/read.js:74:3)<br> &nbsp; &nbsp;at jsonParser (/ms-playwright-agent/node_modules/body-parser/lib/types/json.js:125:5)<br> &nbsp; &nbsp;at Layer.handleRequest (/ms-playwright-agent/node_modules/router/lib/layer.js:152:17)<br> &nbsp; &nbsp;at trimPrefix (/ms-playwright-agent/node_modules/router/index.js:342:13)<br> &nbsp; &nbsp;at /ms-playwright-agent/node_modules/router/index.js:297:9<br> &nbsp; &nbsp;at processParams (/ms-playwright-agent/node_modules/router/index.js:582:12)<br> &nbsp; &nbsp;at next (/ms-playwright-agent/node_modules/router/index.js:291:5)<br> &nbsp; &nbsp;at Function.handle (/ms-playwright-agent/node_modules/router/index.js:186:3)</pre>
</body>
</html>];

like( dies { Playwright::Util::request('tickle','chase', 'localhost', 666, LWP::UserAgent->new(), a => 'b' ) }, qr/^error decoding Playwright server response:/i, "Non-JSON response from server = BOOM");

$json = '{ "error":false, "message": { "_type":"Bogus", "_guid":"abc123" } }';

is(Playwright::Util::request('tickle','chase', 'localhost', 666, LWP::UserAgent->new(), a => 'b' ), { _type => 'Bogus', _guid => 'abc123' }, "Good response from server decoded and returned");

subtest "File payload buffers are base64'd for the server" => sub {
    my $sent;
    $lwpmock->redefine('request', sub {
        my ( $ua, $req ) = @_;
        $sent = JSON::MaybeXS::decode_json( $req->content );
        return bless({},'BogusResponse');
    });
    $json = '{ "error":false, "message":null }';

    my $bytes   = join '', map { chr } 0 .. 255;
    my $payload = { name => 'a.bin', mimeType => 'application/octet-stream', buffer => $bytes };
    my $args    = [ '#f', [ $payload ], { multipart => { upload => $payload, note => 'hi' } }, { buffer => 'not a file' }, { force => JSON::MaybeXS::true() } ];

    Playwright::Util::request( 'POST', 'command', 'localhost', 666, LWP::UserAgent->new(), args => $args );

    my $encoded = { base64 => MIME::Base64::encode_base64( $bytes, '' ) };
    is( $sent->{args}[1][0]{buffer}, $encoded, "File payload in an array is encoded" );
    is( $sent->{args}[2]{multipart}{upload}{buffer}, $encoded, "File payload nested in a hash is encoded" );
    is( $sent->{args}[2]{multipart}{note}, 'hi', "Neighbouring values are untouched" );
    is( $sent->{args}[3]{buffer}, 'not a file', "A buffer outside a file payload is untouched" );
    is( $sent->{args}[4]{force}, T(), "Blessed values such as JSON booleans pass through" );
    is( $payload->{buffer}, $bytes, "Caller's payload is not modified" );

    my $wide = [ { name => 'a.txt', mimeType => 'text/plain', buffer => "\x{263A}" } ];
    like(
        dies { Playwright::Util::request( 'POST', 'command', 'localhost', 666, LWP::UserAgent->new(), args => $wide ) },
        qr/^Wide character/,
        "A buffer of characters, not bytes, dies before anything is sent, as the POD says",
    );
};

#Not testing async/await, mocking forks is bogus

done_testing();
