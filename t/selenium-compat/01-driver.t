use strict;
use warnings;
use v5.28;
no warnings 'experimental';
use feature qw{signatures};
use Test2::V0;
use Test::MockModule;
use Test::Fatal qw{exception};

# Pre-define stub packages for Playwright's generated classes
# so Test::MockModule doesn't try to load the (non-existent) .pm files.
# This must happen before require Playwright and before MockModule calls.
BEGIN {
    for my $pkg (qw{Playwright::ModuleList
                     Playwright::Page Playwright::Browser Playwright::BrowserContext
                     Playwright::ElementHandle Playwright::Frame Playwright::Keyboard
                     Playwright::Mouse Playwright::Dialog Playwright::Locator}) {
        (my $file = $pkg) =~ s{::}{/}g;
        $file .= '.pm';
        $INC{$file} = 1;  # Prevent require from trying to load files
        eval "package $pkg; 1;";
    }
}

# De-fang Playwright's BEGIN block (same pattern as t/Playwright.t)
no warnings qw{redefine once};
$Playwright::SKIP_BEGIN = 1;
use warnings;

require Playwright;

my $mock_pw = Test::MockModule->new('Playwright');
my $mock_base = Test::MockModule->new('Playwright::Base');

my %call_log;

# Mock page object
my $mock_page = bless {
    guid => 'page-1',
    type => 'Page',
    _viewport => { width => 1024, height => 768 },
    _url => 'about:blank',
    _title => '',
    _content => '<html></html>',
}, 'Playwright::Page';

# Mock context object
my $mock_context = bless {
    guid => 'context-1',
    type => 'BrowserContext',
    _cookies => [],
    _pages => [$mock_page],
}, 'Playwright::BrowserContext';

# Mock browser object
my $mock_browser = bless {
    guid => 'browser-1',
    type => 'Browser',
}, 'Playwright::Browser';

# Track method calls on page
my $mock_page_mod = Test::MockModule->new('Playwright::Page');
$mock_page_mod->mock('goto', sub ($self, $url, @rest) {
    $self->{_url} = $url;
    $call_log{goto} = $url;
    return {};
});
$mock_page_mod->mock('url', sub ($self) { return $self->{_url} });
$mock_page_mod->mock('title', sub ($self) { return $self->{_title} });
$mock_page_mod->mock('content', sub ($self) { return $self->{_content} });
$mock_page_mod->mock('goBack', sub ($self) { $call_log{goBack} = 1; return });
$mock_page_mod->mock('goForward', sub ($self) { $call_log{goForward} = 1; return });
$mock_page_mod->mock('reload', sub ($self) { $call_log{reload} = 1; return });
$mock_page_mod->mock('viewportSize', sub ($self) { return $self->{_viewport} });
$mock_page_mod->mock('setViewportSize', sub ($self, $size) { $self->{_viewport} = $size; return });
$mock_page_mod->mock('setDefaultNavigationTimeout', sub ($self, $ms) { $call_log{setDefaultNavigationTimeout} = $ms; return });
$mock_page_mod->mock('screenshot', sub ($self, @args) { return 'base64data' });
$mock_page_mod->mock('evaluate', sub ($self, $script, @args) {
    $call_log{evaluate} = $script;
    return 'eval_result';
});
$mock_page_mod->mock('evaluateHandle', sub ($self, $script, @args) {
    return bless { guid => 'eh-active' }, 'Playwright::ElementHandle';
});
$mock_page_mod->mock('close', sub ($self) { $call_log{page_close} = 1; return });
$mock_page_mod->mock('waitForEvent', sub ($self, $event) {
    $call_log{waitForEvent} = $event;
    return 'dialog_promise';
});
$mock_page_mod->mock('on', sub ($self, @args) {
    $call_log{page_on} = \@args;
    return;
});
$mock_page_mod->mock('select', sub ($self, $selector) {
    $call_log{select} = $selector;
    return bless { guid => 'eh-1' }, 'Playwright::ElementHandle';
});
$mock_page_mod->mock('selectMulti', sub ($self, $selector) {
    $call_log{selectMulti} = $selector;
    return [
        bless({ guid => 'eh-1' }, 'Playwright::ElementHandle'),
        bless({ guid => 'eh-2' }, 'Playwright::ElementHandle'),
    ];
});
$mock_page_mod->mock('frames', sub ($self) { return [] });
$mock_page_mod->mock('mainFrame', sub ($self) {
    return bless { guid => 'frame-main' }, 'Playwright::Frame';
});

# Mock keyboard/mouse
my $mock_keyboard = bless {}, 'Playwright::Keyboard';
my $mock_mouse = bless {}, 'Playwright::Mouse';
$mock_page_mod->mock('keyboard', sub { return $mock_keyboard });
$mock_page_mod->mock('mouse', sub { return $mock_mouse });

my $mock_keyboard_mod = Test::MockModule->new('Playwright::Keyboard');
$mock_keyboard_mod->mock('type', sub ($self, $text, @rest) { $call_log{kb_type} = $text; return });
$mock_keyboard_mod->mock('press', sub ($self, $key, @rest) { $call_log{kb_press} = $key; return });
$mock_keyboard_mod->mock('down', sub ($self, $key) { $call_log{kb_down} = $key; return });
$mock_keyboard_mod->mock('up', sub ($self, $key) { $call_log{kb_up} = $key; return });

my $mock_mouse_mod = Test::MockModule->new('Playwright::Mouse');
$mock_mouse_mod->mock('click', sub ($self, @args) { $call_log{mouse_click} = \@args; return });
$mock_mouse_mod->mock('move', sub ($self, @args) { $call_log{mouse_move} = \@args; return });
$mock_mouse_mod->mock('dblclick', sub ($self, @args) { return });
$mock_mouse_mod->mock('down', sub ($self, @args) { return });
$mock_mouse_mod->mock('up', sub ($self, @args) { return });

# Mock browser
my $mock_browser_mod = Test::MockModule->new('Playwright::Browser');
$mock_browser_mod->mock('newPage', sub ($self, @args) { return $mock_page });
$mock_browser_mod->mock('contexts', sub ($self) { return [$mock_context] });
$mock_browser_mod->mock('close', sub ($self) { $call_log{browser_close} = 1; return });

# Mock context
my $mock_context_mod = Test::MockModule->new('Playwright::BrowserContext');
$mock_context_mod->mock('pages', sub ($self) { return $self->{_pages} });
$mock_context_mod->mock('cookies', sub ($self) { return $self->{_cookies} });
$mock_context_mod->mock('addCookies', sub ($self, $cookies) {
    push @{$self->{_cookies}}, @$cookies;
    return;
});
$mock_context_mod->mock('clearCookies', sub ($self, @args) {
    if (@args && ref $args[0] eq 'HASH' && $args[0]{name}) {
        $self->{_cookies} = [ grep { $_->{name} ne $args[0]{name} } @{$self->{_cookies}} ];
    } else {
        $self->{_cookies} = [];
    }
    return;
});

# Mock ElementHandle
my $mock_eh_mod = Test::MockModule->new('Playwright::ElementHandle');
$mock_eh_mod->mock('click', sub ($self, @args) { $call_log{eh_click} = 1; return });
$mock_eh_mod->mock('fill', sub ($self, $text, @args) { $call_log{eh_fill} = $text; return });
$mock_eh_mod->mock('type', sub ($self, $text, @args) { $call_log{eh_type} = $text; return });
$mock_eh_mod->mock('focus', sub ($self) { $call_log{eh_focus} = 1; return });
$mock_eh_mod->mock('innerText', sub ($self) { return 'element text' });
$mock_eh_mod->mock('getAttribute', sub ($self, $name) { return "attr-$name" });
$mock_eh_mod->mock('evaluate', sub ($self, $script, @args) { return 'eval_result' });
$mock_eh_mod->mock('isVisible', sub ($self) { return 1 });
$mock_eh_mod->mock('isHidden', sub ($self) { return 0 });
$mock_eh_mod->mock('isEnabled', sub ($self) { return 1 });
$mock_eh_mod->mock('isChecked', sub ($self) { return 0 });
$mock_eh_mod->mock('boundingBox', sub ($self) { return { x => 10, y => 20, width => 100, height => 50 } });
$mock_eh_mod->mock('select', sub ($self, $sel) { return bless { guid => 'eh-child' }, 'Playwright::ElementHandle' });
$mock_eh_mod->mock('selectMulti', sub ($self, $sel) { return [ bless { guid => 'eh-child' }, 'Playwright::ElementHandle' ] });
$mock_eh_mod->mock('screenshot', sub ($self, @args) { return 'element_screenshot' });
$mock_eh_mod->mock('scrollIntoViewIfNeeded', sub ($self) { return });
$mock_eh_mod->mock('contentFrame', sub ($self) {
    return bless { guid => 'frame-child' }, 'Playwright::Frame';
});
$mock_eh_mod->mock('check', sub ($self) { return });
$mock_eh_mod->mock('uncheck', sub ($self) { return });

# Mock Playwright constructor and launch
$mock_pw->mock('new', sub ($class, @args) {
    return bless {
        ua   => 'fake',
        port => 1234,
        host => 'localhost',
    }, $class;
});
$mock_pw->mock('launch', sub ($self, %args) { return $mock_browser });
$mock_pw->mock('quit', sub ($self) { $call_log{pw_quit} = 1; return });
$mock_pw->mock('await', sub ($self, $promise) {
    return bless { _message => 'test alert' }, 'Playwright::Dialog';
});
$mock_pw->mock('pusht', sub ($self, @args) { return });
$mock_pw->mock('popt', sub ($self, @args) { return });
$mock_pw->mock('try_until', sub ($self, $target, $method, @args) {
    return $target->$method(@args);
});

# Mock Dialog
my $mock_dialog_mod = Test::MockModule->new('Playwright::Dialog');
$mock_dialog_mod->mock('message', sub ($self) { return $self->{_message} });
$mock_dialog_mod->mock('accept', sub ($self, @args) { $call_log{dialog_accept} = \@args; return });
$mock_dialog_mod->mock('dismiss', sub ($self) { $call_log{dialog_dismiss} = 1; return });

# Now load SeleniumMigrator
require Playwright::SeleniumMigrator;

# ==============================
# Tests
# ==============================

subtest "Constructor" => sub {
    %call_log = ();
    my $driver = Selenium::Remote::Driver->new(
        browser_name => 'chrome',
        auto_close   => 0,
    );
    ok($driver, 'Driver created');
    is(ref $driver, 'Selenium::Remote::Driver', 'Correct class');
    ok($driver->{_pw}, 'Has Playwright handle');
    ok($driver->{_browser}, 'Has browser');
    ok($driver->{_page}, 'Has page');
    ok($driver->{_context}, 'Has context');
    is($driver->{_auto_close}, 0, 'auto_close set to 0');
    is($driver->{_default_finder}, 'xpath', 'Default finder is xpath');

    # Clean up without auto-close
    $driver->quit();
    ok($call_log{browser_close}, 'Browser was closed on quit');
    ok($call_log{pw_quit}, 'Playwright was quit');
};

subtest "Constructor with base_url" => sub {
    my $driver = Selenium::Remote::Driver->new(
        browser_name => 'firefox',
        base_url     => 'http://localhost:8080',
        auto_close   => 0,
    );
    is($driver->{_base_url}, 'http://localhost:8080', 'base_url stored');
    $driver->{_auto_close} = 0;
};

subtest "Constructor with inner_window_size" => sub {
    my $driver = Selenium::Remote::Driver->new(
        browser_name     => 'chrome',
        inner_window_size => [600, 800],
        auto_close       => 0,
    );
    my $vp = $mock_page->{_viewport};
    is($vp->{height}, 600, 'Height set from inner_window_size');
    is($vp->{width}, 800, 'Width set from inner_window_size');
    $driver->{_auto_close} = 0;
};

subtest "Navigation" => sub {
    %call_log = ();
    my $driver = Selenium::Remote::Driver->new(auto_close => 0);

    $driver->get('http://example.com');
    is($call_log{goto}, 'http://example.com', 'get() calls goto with URL');

    $mock_page->{_url} = 'http://example.com';
    is($driver->get_current_url(), 'http://example.com', 'get_current_url returns URL');

    $mock_page->{_title} = 'Example Page';
    is($driver->get_title(), 'Example Page', 'get_title returns title');

    $driver->go_back();
    ok($call_log{goBack}, 'go_back calls goBack');

    $driver->go_forward();
    ok($call_log{goForward}, 'go_forward calls goForward');

    $driver->refresh();
    ok($call_log{reload}, 'refresh calls reload');

    $mock_page->{_content} = '<html><body>Hello</body></html>';
    is($driver->get_page_source(), '<html><body>Hello</body></html>', 'get_page_source returns content');

    $driver->{_auto_close} = 0;
};

subtest "Navigation with base_url" => sub {
    %call_log = ();
    my $driver = Selenium::Remote::Driver->new(
        base_url   => 'http://localhost:3000',
        auto_close => 0,
    );
    $driver->get('/test-page');
    is($call_log{goto}, 'http://localhost:3000/test-page', 'Relative URL resolved with base_url');

    $driver->get('http://other.com/page');
    is($call_log{goto}, 'http://other.com/page', 'Absolute URL passed through');
    $driver->{_auto_close} = 0;
};

subtest "Element Finding" => sub {
    %call_log = ();
    my $driver = Selenium::Remote::Driver->new(auto_close => 0);

    my $el = $driver->find_element('#test', 'css');
    ok($el, 'find_element returns element');
    is(ref $el, 'Selenium::Remote::WebElement', 'Correct WebElement class');
    is($call_log{select}, '#test', 'CSS selector passed through');

    $driver->find_element('myid', 'id');
    is($call_log{select}, '#myid', 'ID strategy translated to CSS #id');

    $driver->find_element('myname', 'name');
    is($call_log{select}, '[name="myname"]', 'Name strategy translated');

    $driver->find_element('myclass', 'class');
    is($call_log{select}, '.myclass', 'Class strategy translated');

    $driver->find_element('h1', 'tag_name');
    is($call_log{select}, 'h1', 'Tag name passed through');

    $driver->find_element('//h1', 'xpath');
    is($call_log{select}, 'xpath=//h1', 'XPath prefixed');

    $driver->find_element('Test Link', 'link_text');
    like($call_log{select}, qr{xpath=//a\[normalize-space}, 'Link text translated to xpath');

    $driver->find_element('Test', 'partial_link_text');
    like($call_log{select}, qr{xpath=//a\[contains}, 'Partial link text translated to xpath');

    $driver->{_auto_close} = 0;
};

subtest "Default Finder" => sub {
    %call_log = ();
    my $driver = Selenium::Remote::Driver->new(
        default_finder => 'css',
        auto_close     => 0,
    );
    $driver->find_element('.test');
    is($call_log{select}, '.test', 'Default finder used when strategy omitted (css)');

    my $driver2 = Selenium::Remote::Driver->new(auto_close => 0);
    $driver2->find_element('//div');
    is($call_log{select}, 'xpath=//div', 'Default finder is xpath');

    $driver->{_auto_close} = 0;
    $driver2->{_auto_close} = 0;
};

subtest "find_elements" => sub {
    %call_log = ();
    my $driver = Selenium::Remote::Driver->new(auto_close => 0);

    my @els = $driver->find_elements('.items', 'css');
    is(scalar @els, 2, 'find_elements returns array');
    is(ref $els[0], 'Selenium::Remote::WebElement', 'Array contains WebElements');

    $driver->{_auto_close} = 0;
};

subtest "Convenience Finders" => sub {
    %call_log = ();
    my $driver = Selenium::Remote::Driver->new(auto_close => 0);

    $driver->find_element_by_id('test');
    is($call_log{select}, '#test', 'find_element_by_id works');

    $driver->find_element_by_css('.test');
    is($call_log{select}, '.test', 'find_element_by_css works');

    $driver->find_element_by_xpath('//div');
    is($call_log{select}, 'xpath=//div', 'find_element_by_xpath works');

    $driver->find_element_by_name('test');
    is($call_log{select}, '[name="test"]', 'find_element_by_name works');

    $driver->find_element_by_tag_name('div');
    is($call_log{select}, 'div', 'find_element_by_tag_name works');

    $driver->{_auto_close} = 0;
};

subtest "WebElement Methods" => sub {
    %call_log = ();
    my $driver = Selenium::Remote::Driver->new(auto_close => 0);
    my $el = $driver->find_element('#test', 'css');

    $el->click();
    ok($call_log{eh_click}, 'click calls ElementHandle click');

    is($el->get_text(), 'element text', 'get_text returns innerText');
    is($el->get_attribute('href'), 'attr-href', 'get_attribute works');
    is($el->is_displayed(), 1, 'is_displayed returns boolean');
    is($el->is_enabled(), 1, 'is_enabled returns boolean');
    is($el->is_selected(), 0, 'is_selected returns boolean');

    my $size = $el->get_size();
    is($size->{width}, 100, 'get_size width');
    is($size->{height}, 50, 'get_size height');

    my $loc = $el->get_element_location();
    is($loc->{x}, 10, 'get_element_location x');
    is($loc->{y}, 20, 'get_element_location y');

    ok($el->id(), 'Element has id');

    $driver->{_auto_close} = 0;
};

subtest "WebElement send_keys" => sub {
    %call_log = ();
    my $driver = Selenium::Remote::Driver->new(auto_close => 0);
    my $el = $driver->find_element('#test', 'css');

    $el->send_keys('hello');
    ok($call_log{eh_click}, 'send_keys clicks to focus element');
    is($call_log{kb_type}, 'hello', 'send_keys types text via page keyboard');

    $driver->{_auto_close} = 0;
};

subtest "WebElement send_keys with special keys" => sub {
    %call_log = ();
    my $driver = Selenium::Remote::Driver->new(auto_close => 0);
    my $el = $driver->find_element('#test', 'css');

    my $KEYS = Selenium::Remote::WDKeys::KEYS();
    $el->send_keys('hello', $KEYS->{enter});
    ok($call_log{kb_press}, 'Special key triggers keyboard press');
    is($call_log{kb_press}, 'Enter', 'Enter key mapped correctly');

    $driver->{_auto_close} = 0;
};

subtest "WebElement clear" => sub {
    %call_log = ();
    my $driver = Selenium::Remote::Driver->new(auto_close => 0);
    my $el = $driver->find_element('#test', 'css');

    $el->clear();
    is($call_log{eh_fill}, '', 'clear fills with empty string');

    $driver->{_auto_close} = 0;
};

subtest "JavaScript Execution" => sub {
    %call_log = ();
    my $driver = Selenium::Remote::Driver->new(auto_close => 0);

    my $result = $driver->execute_script('return 42');
    is($call_log{evaluate}, 'return 42', 'execute_script calls evaluate');

    $driver->{_auto_close} = 0;
};

subtest "Window Management" => sub {
    %call_log = ();
    my $driver = Selenium::Remote::Driver->new(auto_close => 0);

    my $handle = $driver->get_current_window_handle();
    ok($handle, 'get_current_window_handle returns a handle');
    like($handle, qr/^CDwindow-/, 'Handle has expected format');

    my $handles = $driver->get_window_handles();
    is(ref $handles, 'ARRAY', 'get_window_handles returns arrayref');
    ok(scalar @$handles >= 1, 'At least one window handle');

    $driver->{_auto_close} = 0;
};

subtest "Window Size" => sub {
    %call_log = ();
    $mock_page->{_viewport} = { width => 1024, height => 768 };
    my $driver = Selenium::Remote::Driver->new(auto_close => 0);

    my $size = $driver->get_window_size();
    is($size->{width}, 1024, 'get_window_size width');
    is($size->{height}, 768, 'get_window_size height');

    $driver->set_window_size(600, 800);
    is($mock_page->{_viewport}{width}, 800, 'set_window_size sets width');
    is($mock_page->{_viewport}{height}, 600, 'set_window_size sets height');

    $driver->maximize_window();
    is($mock_page->{_viewport}{width}, 1920, 'maximize sets large width');

    $driver->{_auto_close} = 0;
};

subtest "Cookies" => sub {
    %call_log = ();
    $mock_context->{_cookies} = [];
    my $driver = Selenium::Remote::Driver->new(auto_close => 0);

    my $cookies = $driver->get_all_cookies();
    is(ref $cookies, 'ARRAY', 'get_all_cookies returns arrayref');
    is(scalar @$cookies, 0, 'No cookies initially');

    $driver->add_cookie(name => 'test', value => '123');
    $cookies = $driver->get_all_cookies();
    is(scalar @$cookies, 1, 'Cookie added');
    is($cookies->[0]{name}, 'test', 'Cookie name correct');

    my $cookie = $driver->get_cookie_named('test');
    is($cookie->{value}, '123', 'get_cookie_named returns correct cookie');

    my $missing = $driver->get_cookie_named('nonexistent');
    ok(!$missing, 'get_cookie_named returns undef for missing cookie');

    $driver->delete_cookie_named('test');
    $cookies = $driver->get_all_cookies();
    is(scalar @$cookies, 0, 'Cookie deleted by name');

    $driver->add_cookie(name => 'a', value => '1');
    $driver->add_cookie(name => 'b', value => '2');
    $driver->delete_all_cookies();
    $cookies = $driver->get_all_cookies();
    is(scalar @$cookies, 0, 'All cookies deleted');

    $driver->{_auto_close} = 0;
};

subtest "Timeouts" => sub {
    my $driver = Selenium::Remote::Driver->new(auto_close => 0);

    $driver->set_timeout('implicit', 5000);
    is($driver->{_implicit_wait}, 5000, 'Implicit wait set');

    $driver->set_implicit_wait_timeout(10000);
    is($driver->{_implicit_wait}, 10000, 'set_implicit_wait_timeout works');

    $driver->set_timeout('script', 15000);
    is($driver->{_script_timeout}, 15000, 'Script timeout set');

    %call_log = ();
    $driver->set_timeout('page load', 60000);
    is($call_log{setDefaultNavigationTimeout}, 60000, 'Page load timeout calls setDefaultNavigationTimeout');

    my $timeouts = $driver->get_timeouts();
    is($timeouts->{implicit}, 10000, 'get_timeouts returns implicit');
    is($timeouts->{script}, 15000, 'get_timeouts returns script');

    $driver->{_auto_close} = 0;
};

subtest "Screenshots" => sub {
    %call_log = ();
    my $driver = Selenium::Remote::Driver->new(auto_close => 0);

    # screenshot() now saves to a temp file and base64-encodes it.
    # The mock screenshot writes 'base64data' as path, so we test
    # capture_screenshot (which just passes through to page.screenshot).
    my $data = $driver->capture_screenshot('/tmp/test_screenshot.png');
    ok($data, 'capture_screenshot returns truthy');

    $driver->{_auto_close} = 0;
};

subtest "Alerts" => sub {
    %call_log = ();
    my $driver = Selenium::Remote::Driver->new(auto_close => 0);

    # Simulate arming the dialog listener (normally done via click())
    $driver->_ensure_dialog_listener();
    ok($call_log{waitForEvent}, 'Dialog listener armed waitForEvent');
    ok($call_log{page_on}, 'Dialog on() handler registered');

    my $text = $driver->get_alert_text();
    is($text, 'test alert', 'get_alert_text returns dialog message');

    # Re-arm for accept test (dialog is auto-accepted by on() handler)
    $driver->_ensure_dialog_listener();
    $driver->accept_alert();
    pass('accept_alert completed without error');

    $driver->{_auto_close} = 0;
};

subtest "Child Elements" => sub {
    %call_log = ();
    my $driver = Selenium::Remote::Driver->new(auto_close => 0);
    my $parent = $driver->find_element('#container', 'css');

    my $child = $parent->child('.item', 'css');
    ok($child, 'child returns element');
    is(ref $child, 'Selenium::Remote::WebElement', 'child returns WebElement');

    my @children = $parent->children('.item', 'css');
    ok(scalar @children >= 1, 'children returns elements');

    $driver->{_auto_close} = 0;
};

subtest "Miscellaneous" => sub {
    my $driver = Selenium::Remote::Driver->new(auto_close => 0);

    ok($driver->has_javascript(), 'has_javascript returns true');

    my $caps = $driver->get_capabilities();
    ok($caps->{browserName}, 'get_capabilities returns browserName');

    my $status = $driver->status();
    ok($status->{ready}, 'status returns ready');

    $driver->{_auto_close} = 0;
};

subtest "Waiter" => sub {
    require Playwright::SeleniumMigrator::Waiter;
    my $counter = 0;
    my $result = Selenium::Waiter::wait_until(sub { ++$counter >= 3 }, timeout => 5);
    ok($result, 'wait_until returns truthy on success');
    is($counter, 3, 'wait_until polled until condition met');

    my $fail = Selenium::Waiter::wait_until(sub { 0 }, timeout => 1, interval => 0.1);
    is($fail, 0, 'wait_until returns 0 on timeout');

    my $ex = exception {
        Selenium::Waiter::wait_until(sub { 0 }, timeout => 0.5, interval => 0.1, die => 1);
    };
    like($ex, qr/Timed out/, 'wait_until dies when die => 1 and timeout');
};

done_testing();
