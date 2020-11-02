use Test2::V0;
use Test2::Tools::Explain;
use JSON::MaybeXS;
use Test::MockModule qw{strict};
use Test::MockFile;
use Async;

my ($qxret,$qxcode) = ('',255);
use Test::Mock::Cmd qx => sub { $? = $qxcode; return $qxret };

#De-Fang our BEGIN block so we can test safely
no warnings qw{redefine once};
$Playwright::SKIP_BEGIN = 1;
use warnings;
require Playwright;

my $path2here = File::Basename::dirname(Cwd::abs_path($INC{'Playwright.pm'}));

subtest "_check_and_build_spec" => sub {
    #Simulate file not existing
    my $json = Test::MockFile->file("$path2here/../share/api.json");
    like( dies { Playwright::_check_and_build_spec() }, qr/specification/i, "Nonexistant api.json throws");

    undef $json;
    $json = Test::MockFile->file("$path2here/../share/api.json", '{"a":"b"}');
    my ($path) = Playwright::_check_and_build_spec();
    is($Playwright::spec, { a => 'b'}, "Spec parsed correctly");
    is($path,$path2here, "Path to module built correctly");
};

subtest "_build_classes" => sub {
    local $Playwright::spec = {
        Fake => {
            members => {
                tickle => {
                    args => {
                        chase => { type => { name => 'boolean' }, order => 1 },
                        tickleOptions => {
                            order => 0,
                            type => {
                                name => 'Object',
                                properties => {
                                    intense  => { name => 'intense',  type => { name => 'boolean' }  },
                                    tickler  => { name => 'tickler',  type => { name => 'string'  }  },
                                    optional => { name => 'optional', type => { name => 'boolean' }  }, # Optional, shouldn't show up in output
                                },
                            },
                        },
                        who => { type => { name => 'string' },  order => 2 },
                        hug => { type => { name => 'boolean' }, order => 3 }, # Optional bool arg, make sure we dont choke
                    },
                },
            }
        },
    };

    #Very light testing here, example.pl is really what tests this
    Playwright::_build_classes();
    ok(defined &Playwright::Fake::new, "Constructors set up correctly");
    ok(defined &Playwright::Fake::tickle, "Class methods set up correctly");
};

subtest "_check_node" => sub {
    my $decoder = JSON::MaybeXS->new();

    my $bin = Test::MockFile->file("$path2here/../bin/playwright_server");

    like( dies { Playwright::_check_node($path2here, $decoder) }, qr/server in/i, "Server not existing throws");

    undef $bin;
    $bin = Test::MockFile->file("$path2here/../bin/playwright_server",'');

    my $which = Test::MockModule->new('File::Which');
    $which->redefine('which', sub { shift eq 'node' ? '/bogus' : '/hokum' });
    my $node = Test::MockFile->file('/bogus', undef, { mode => 0777 } );
    my $npm  = Test::MockFile->file('/hokum', undef, { mode => 0777 } );

    like( dies { Playwright::_check_node($path2here, $decoder) }, qr/node must exist/i, "node not existing throws");
    undef $node;
    $node = Test::MockFile->file('/bogus', '', { mode => 0777 } );

    like( dies { Playwright::_check_node($path2here, $decoder) }, qr/npm must exist/i, "npm not existing throws");
    undef $npm;
    $npm  = Test::MockFile->file('/hokum', '', { mode => 0777 } );

    my $fakecapture = Test::MockModule->new('Capture::Tiny');
    $fakecapture->redefine('capture_stderr', sub { 'oh no' });

    $qxret = '';
    like( dies { Playwright::_check_node($path2here, $decoder) }, qr/could not list/i, "package.json not existing throws");

    $qxret = '{
        "name": "playwright-server-perl",
          "version": "1.0.0",
          "problems": [
            "missing: express@^4.17, required by playwright-server-perl@1.0.0",
            "missing: playwright@^1.5, required by playwright-server-perl@1.0.0",
            "missing: yargs@^16.1, required by playwright-server-perl@1.0.0",
            "missing: uuid@^8.3, required by playwright-server-perl@1.0.0"
          ],
          "dependencies": {
            "express": {
              "required": "^4.17",
              "missing": true
            },
            "playwright": {
              "required": "^1.5",
              "missing": true
            },
            "yargs": {
              "required": "^16.1",
              "missing": true
            },
            "uuid": {
              "required": "^8.3",
              "missing": true
            }
          }
    }';

    #XXX doesn't look like we can mock $? correctly
    #like( dies { Playwright::_check_node($path2here, $decoder) }, qr/installing node/i, "npm failure throws");
    $fakecapture->redefine('capture_stderr', sub { 'package-lock' });
    $qxcode = 0;
    ok( lives { Playwright::_check_node($path2here, $decoder) }, "Can run all the way thru") or note $@;
};

subtest "new" => sub {
    my $portmock = Test::MockModule->new('Net::EmptyPort');
    $portmock->redefine('empty_port', sub { 420 });

    my $lwpmock = Test::MockModule->new('LWP::UserAgent');
    $lwpmock->redefine('new', sub { 'LWP' });

    my $selfmock = Test::MockModule->new('Playwright');
    $selfmock->redefine('_start_server', sub { 666 });
    $selfmock->redefine('DESTROY', sub {});

    my $expected = bless({
        ua     => 'whee',
        debug  => 1,
        parent => $$,
        pid    => 666,
        port   => 420,
    }, 'Playwright');

    is(Playwright->new( ua => 'whee', debug => 1), $expected, "Constructor functions as expected");

    $expected = bless({
        ua     => 'LWP',
        debug  => undef,
        parent => $$,
        pid    => 666,
        port   => 420,
    }, 'Playwright');

    is(Playwright->new(), $expected, "Constructor defaults expected");
};

subtest "launch" => sub {
    my $basemock = Test::MockModule->new('Playwright::Base');
    $basemock->redefine('_coerce', sub {});
    my $utilmock = Test::MockModule->new('Playwright::Util');
    $utilmock->redefine('request', sub { 'eee' });
    my $selfmock = Test::MockModule->new('Playwright');
    $selfmock->redefine('DESTROY', sub {});

    my $obj = bless({}, 'Playwright');
    is($obj->launch( type => 'eee' ), 'eee' ,"launch passthru works");

    #XXX Don't feel like mocking the objectification right now
};

subtest "await" => sub {
    my $selfmock = Test::MockModule->new('Playwright');
    $selfmock->redefine('DESTROY', sub {});

    my $res = {};

    no warnings qw{redefine once};
    local *AsyncData::result = sub { $res };
    use warnings;

    my $promise = bless({},'AsyncData');

    my $obj = bless({ ua => 'eee', 'port' => 1 }, 'Playwright');
    no warnings qw{redefine once};
    local *Playwright::Bogus::new = sub { my ($class, %input) = @_; return bless({ spec => 'whee', ua => $input{handle}{ua}, port => $input{handle}{port}, type => $input{type}, guid => $input{id} }, 'Playwright::Bogus') };
    use warnings;

    is($obj->await($promise),{},"await passthru works");

    $res = { _guid => 'abc123', _type => 'Bogus' };
    my $expected = bless({ spec => 'whee', ua => 'eee', port => 1, guid => 'abc123', type => 'Bogus' }, 'Bogus');
    is($obj->await($promise),$expected,"await objectification works");

};

#XXX Omitting destructor and server startup testing for now

done_testing();
