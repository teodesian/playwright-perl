use Test2::V0 -target => 'Playwright::Base';
use Test2::Tools::Explain;
use Playwright::Base;
use JSON;
use Test::MockModule qw{strict};

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

local %Playwright::mapper = (
    Fake => sub {
        my ($self, $res) = @_;
        my $class = "Playwright::Fake";
        return $class->new( handle => $self, id => $res->{_guid}, type => 'Fake', spec => $Playwright::spec->{Fake} );
    },
);

no warnings qw{redefine once};
local *Playwright::Fake::new = sub {
    my ($class,%options) = @_;
    return bless( {
        spec => $Playwright::spec->{$options{type}}{members},
        type => $options{type},
        guid => $options{id},
        ua   => $options{handle}{ua},
        port => $options{handle}{port},
    }, $class);
};
use warnings;

my $obj = CLASS()->new(
    type => 'Fake',
    id   => 666,
    handle => { ua => 'bogus', port => 420 },
);

is($obj->{spec}, $Playwright::spec->{Fake}{members}, "Spec correctly filed by constructor");

my %in = (
    command => 'tickle',
    type    => 'Fake',
    args    => [{ intense => 1, tickler => 'bigtime' },0, 'boom'],
);

my %expected = (
    command => 'tickle',
    type    => 'Fake',
    args    => [{ intense => JSON::true, tickler => 'bigtime' }, JSON::false, 'boom'],
);

my %out = Playwright::Base::_coerce($obj->{spec}, %in);

is(\%out, \%expected, "_coerce correctly transforms bools and leaves everything else alone");

my $result = { error => JSON::true, message => "U suck" };

my $utilmock = Test::MockModule->new('Playwright::Util');
$utilmock->redefine('request', sub {
    return $result;
});

is( $obj->_api_request(%in), $result, "Data directly returned when no _type or _guid");
$result = { _guid => 666, _type => 'Fake' };
my $exp_obj = Playwright::Fake->new(
    id     => 666,
    type   => 'Fake',
    spec   => $Playwright::spec->{Fake}{members},
    handle => $obj
);
my $oot = $obj->_api_request(%in);

is( $oot, $exp_obj, "Object returned when _type or _guid returned");

done_testing();
