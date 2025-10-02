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

#Not testing async/await, mocking forks is bogus

done_testing();
