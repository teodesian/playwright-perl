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

like( dies { Playwright::Util::request('tickle','chase',666, LWP::UserAgent->new(), a => 'b' ) }, qr/waa/i, "Bad response from server = BOOM");

$json = '{ "error":false, "message": { "_type":"Bogus", "_guid":"abc123" } }';

is(Playwright::Util::request('tickle','chase',666, LWP::UserAgent->new(), a => 'b' ), { _type => 'Bogus', _guid => 'abc123' }, "Good response from server decoded and returned");

done_testing();
