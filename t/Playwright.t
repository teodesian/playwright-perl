use Test2::V0;
use Test2::Tools::Explain;
use JSON::MaybeXS;
use Test::MockModule qw{strict};
use Test::MockFile;
use Test::Fatal qw{exception};

my ($qxret,$qxcode) = ('',255);
use Test::Mock::Cmd qx => sub { $? = $qxcode; return $qxret }, system => sub { print $qxret };

#De-Fang our BEGIN block so we can test safely
no warnings qw{redefine once};
$Playwright::SKIP_BEGIN = 1;
use warnings;
require Playwright;

my $path2here = File::Basename::dirname(Cwd::abs_path($INC{'Playwright.pm'}));

subtest "_check_and_build_spec" => sub {
    local $Playwright::spec = {};

    is(Playwright::_check_and_build_spec({}),{},"Already defined spec short-circuits");

    my $utilmock = Test::MockModule->new('Playwright::Util');
    $utilmock->redefine('request', sub { 'eee' });

    undef $Playwright::spec;
    like(exception { Playwright::_check_and_build_spec({ ua => 'eeep', port => 666} ) },qr/Could not retrieve/,"Fetch explodes when playwright_server doesn't have spec");
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
    my $which = Test::MockModule->new('File::Which');

    my %to_return = (
        node => '/bogus',
        npm  => '/hokum',
        playwright_server => "$path2here/../bin/playwright_server",
    );

    $which->redefine('which', sub { my $to = shift; $to_return{$to} } );
    my $node = Test::MockFile->file('/bogus', undef, { mode => 0777 } );
    my $npm  = Test::MockFile->file('/hokum', undef, { mode => 0777 } );

    like( dies { Playwright::_check_node() }, qr/node must exist/i, "node not existing throws");
    undef $node;
    $node = Test::MockFile->file('/bogus', '', { mode => 0777 } );

    my $bin = Test::MockFile->file("$path2here/../bin/playwright_server");
    like( dies { Playwright::_check_node() }, qr/server in/i, "Server not existing throws");

    undef $bin;
    $bin = Test::MockFile->file("$path2here/../bin/playwright_server",'');

    like( dies { Playwright::_check_node() }, qr/npm must exist/i, "npm not existing throws");
    undef $npm;
    $npm  = Test::MockFile->file('/hokum', '', { mode => 0777 } );

    my $fakecapture = Test::MockModule->new('Capture::Tiny');
    $fakecapture->redefine('capture_stderr', sub { 'oh no' });

    my $pmock = Test::MockModule->new('File::pushd');
    $pmock->redefine('pushd', sub {shift});

    #XXX doesn't look like we can mock $? correctly
    #like( dies { Playwright::_check_node($path2here, $decoder) }, qr/installing node/i, "npm failure throws");
    $fakecapture->redefine('capture_stderr', sub { 'package-lock' });
    $qxcode = 0;
    ok( lives { Playwright::_check_node() }, "Can run all the way thru") or note $@;
};

subtest "new" => sub {
    my $portmock = Test::MockModule->new('Net::EmptyPort');
    $portmock->redefine('empty_port', sub { 420 });

    my $lwpmock = Test::MockModule->new('LWP::UserAgent');
    $lwpmock->redefine('new', sub { bless({},'LWP::UserAgent') });
    $lwpmock->redefine('request', sub {});

    my $selfmock = Test::MockModule->new('Playwright');
    $selfmock->redefine('_start_server', sub { 666 });
    $selfmock->redefine('_check_and_build_spec', sub {});
    $selfmock->redefine('_build_classes',sub {});
    $selfmock->redefine('DESTROY', sub {});

    my $expected = bless({
        ua     => 'whee',
        debug  => 1,
        parent => $$,
        pid    => 666,
        port   => 420,
        timeout => 5,
    }, 'Playwright');

    is(Playwright->new( timeout => 5, ua => 'whee', debug => 1), $expected, "Constructor functions as expected");

    $expected = bless({
        ua     => bless({},'LWP::UserAgent'),
        debug  => undef,
        parent => $$,
        pid    => 666,
        port   => 420,
        timeout => 30,
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

    my $utilmock = Test::MockModule->new('Playwright::Util');
    $utilmock->redefine('await', sub { $res } );

    my $promise = { file => 'foo.out', pid => 666 };

    my $obj = bless({ ua => 'eee', 'port' => 1 }, 'Playwright');
    no warnings qw{redefine once};
    local *Playwright::Bogus::new = sub { my ($class, %input) = @_; return bless({ spec => 'whee', ua => $input{handle}{ua}, port => $input{handle}{port}, type => $input{type}, guid => $input{id} }, 'Playwright::Bogus') };
    use warnings;

    is($obj->await($promise), {},"await passthru works");

    $res = { _guid => 'abc123', _type => 'Bogus' };
    my $expected = bless({ spec => 'whee', ua => 'eee', port => 1, guid => 'abc123', type => 'Bogus' }, 'Bogus');
    is($obj->await($promise),$expected,"await objectification works");

};

#XXX Omitting destructor and server startup testing for now

done_testing();
