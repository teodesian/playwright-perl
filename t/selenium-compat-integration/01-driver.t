use strict;
use warnings;

use FindBin::libs;

use Test2::V0;
use Test::Fatal qw{exception};
use File::Basename;
use Cwd qw{abs_path};

use Playwright::SeleniumMigrator;

# Skip unless explicitly requested or generated files are present
BEGIN {
    skip_all('Set PLAYWRIGHT_INTEGRATION=1 or AUTHOR_TESTING=1 to run integration tests')
        unless $ENV{PLAYWRIGHT_INTEGRATION} || $ENV{AUTHOR_TESTING};
}

# Try to create a driver - skip if environment not built (no playwright_server, etc.)
my $_test_driver = eval { Selenium::Remote::Driver->new(browser_name => 'chrome', auto_close => 0) };
if (!$_test_driver) {
    skip_all("Cannot create Playwright driver (run 'dzil build' or install deps first): $@");
}
$_test_driver->quit();
undef $_test_driver;

my $test_dir = abs_path(dirname(__FILE__) . '/../selenium-compat/test-pages');

sub file_url {
    my ($filename) = @_;
    return "file://$test_dir/$filename";
}

# ==============================
# Constructor & Lifecycle
# ==============================

subtest "Constructor and quit" => sub {
    my $driver = Selenium::Remote::Driver->new(
        browser_name => 'chrome',
        auto_close   => 0,
    );
    ok($driver, 'Driver created with chrome');
    is(ref $driver, 'Selenium::Remote::Driver', 'Correct class');
    $driver->quit();
    pass('quit completed without error');
};

# ==============================
# Navigation
# ==============================

subtest "Navigation" => sub {
    my $driver = Selenium::Remote::Driver->new(
        browser_name => 'chrome',
        auto_close   => 0,
    );

    $driver->get(file_url('index.html'));
    like($driver->get_current_url(), qr/index\.html/, 'URL contains index.html');
    is($driver->get_title(), 'Test Page', 'Title is correct');

    my $source = $driver->get_page_source();
    like($source, qr/Test Heading/, 'Page source contains expected content');

    # Navigate to form page
    $driver->get(file_url('form.html'));
    is($driver->get_title(), 'Form Page', 'Navigated to form page');

    # Back
    $driver->go_back();
    like($driver->get_current_url(), qr/index\.html/, 'go_back returns to index');

    # Forward
    $driver->go_forward();
    like($driver->get_current_url(), qr/form\.html/, 'go_forward goes to form');

    # Refresh
    $driver->refresh();
    like($driver->get_current_url(), qr/form\.html/, 'URL still form after refresh');

    $driver->quit();
};

# ==============================
# Element Finding
# ==============================

subtest "find_element by various strategies" => sub {
    my $driver = Selenium::Remote::Driver->new(
        browser_name => 'chrome',
        auto_close   => 0,
    );
    $driver->get(file_url('index.html'));

    # By ID
    my $heading = $driver->find_element('heading', 'id');
    ok($heading, 'Found element by id');
    is($heading->get_text(), 'Test Heading', 'Element text correct');

    # By CSS
    my $p = $driver->find_element('.content', 'css');
    ok($p, 'Found element by css');
    is($p->get_text(), 'Hello World', 'CSS element text correct');

    # By tag name
    my $h1 = $driver->find_element('h1', 'tag_name');
    ok($h1, 'Found element by tag_name');

    # By name
    my $input = $driver->find_element('username', 'name');
    ok($input, 'Found element by name');

    # By xpath
    my $xpath_el = $driver->find_element('//h1[@id="heading"]', 'xpath');
    ok($xpath_el, 'Found element by xpath');
    is($xpath_el->get_text(), 'Test Heading', 'XPath element text correct');

    # By link text
    my $link = $driver->find_element('Form Link', 'link_text');
    ok($link, 'Found element by link_text');

    # By partial link text
    my $partial = $driver->find_element('Form', 'partial_link_text');
    ok($partial, 'Found element by partial_link_text');

    # Element not found
    my $ex = exception { $driver->find_element('nonexistent', 'id') };
    ok($ex, 'Exception thrown for missing element');

    $driver->quit();
};

subtest "find_elements" => sub {
    my $driver = Selenium::Remote::Driver->new(
        browser_name => 'chrome',
        auto_close   => 0,
    );
    $driver->get(file_url('index.html'));

    my @paragraphs = $driver->find_elements('.content', 'css');
    is(scalar @paragraphs, 2, 'Found 2 content paragraphs');
    is($paragraphs[0]->get_text(), 'Hello World', 'First paragraph text');
    is($paragraphs[1]->get_text(), 'Second Paragraph', 'Second paragraph text');

    $driver->quit();
};

subtest "Convenience finders" => sub {
    my $driver = Selenium::Remote::Driver->new(
        browser_name => 'chrome',
        auto_close   => 0,
    );
    $driver->get(file_url('index.html'));

    ok($driver->find_element_by_id('heading'), 'find_element_by_id works');
    ok($driver->find_element_by_css('.content'), 'find_element_by_css works');
    ok($driver->find_element_by_xpath('//h1'), 'find_element_by_xpath works');
    ok($driver->find_element_by_name('username'), 'find_element_by_name works');
    ok($driver->find_element_by_tag_name('h1'), 'find_element_by_tag_name works');

    $driver->quit();
};

subtest "Child elements" => sub {
    my $driver = Selenium::Remote::Driver->new(
        browser_name => 'chrome',
        auto_close   => 0,
    );
    $driver->get(file_url('index.html'));

    my $container = $driver->find_element('container', 'id');
    my $child = $driver->find_child_element($container, '.child', 'css');
    ok($child, 'Found child element');
    is($child->get_text(), 'Child 1', 'First child text');

    my @children = $driver->find_child_elements($container, '.child', 'css');
    is(scalar @children, 3, 'Found 3 child elements');

    $driver->quit();
};

# ==============================
# WebElement Methods
# ==============================

subtest "WebElement interactions" => sub {
    my $driver = Selenium::Remote::Driver->new(
        browser_name => 'chrome',
        auto_close   => 0,
    );
    $driver->get(file_url('form.html'));

    # Text input
    my $fname = $driver->find_element('fname', 'id');
    $fname->send_keys('John');
    is($fname->get_value(), 'John', 'send_keys typed text');

    $fname->clear();
    is($fname->get_value(), '', 'clear emptied input');

    # Attributes
    is($fname->get_attribute('placeholder'), 'First Name', 'get_attribute works');
    is($fname->get_tag_name(), 'input', 'get_tag_name returns lowercase tag');

    # Visibility
    ok($fname->is_displayed(), 'Visible element is_displayed');
    ok($fname->is_enabled(), 'Enabled element is_enabled');

    # Disabled element
    my $disabled = $driver->find_element('disabled-input', 'id');
    ok(!$disabled->is_enabled(), 'Disabled element is not enabled');

    # Checkbox
    my $cb1 = $driver->find_element('cb1', 'id');
    ok(!$cb1->is_selected(), 'Unchecked checkbox is not selected');
    $cb1->click();
    ok($cb1->is_selected(), 'Checkbox selected after click');

    my $cb2 = $driver->find_element('cb2', 'id');
    ok($cb2->is_selected(), 'Pre-checked checkbox is selected');

    # Click counting
    my $count_btn = $driver->find_element('count-btn', 'id');
    $count_btn->click();
    my $count = $driver->find_element('count', 'id');
    is($count->get_text(), '1', 'Click handler fired');

    $count_btn->click();
    is($count->get_text(), '2', 'Second click counted');

    # CSS
    my $colored = $driver->find_element('colored-div', 'id');
    my $color = $colored->get_css_attribute('color');
    ok($color, 'get_css_attribute returns a value');

    # Size and location
    my $size = $colored->get_size();
    ok($size->{width} > 0, 'get_size returns positive width');
    ok($size->{height} > 0, 'get_size returns positive height');

    my $loc = $colored->get_element_location();
    ok(defined $loc->{x}, 'get_element_location returns x');
    ok(defined $loc->{y}, 'get_element_location returns y');

    $driver->quit();
};

subtest "WebElement send_keys with special keys" => sub {
    my $driver = Selenium::Remote::Driver->new(
        browser_name => 'chrome',
        auto_close   => 0,
    );
    $driver->get(file_url('form.html'));

    my $KEYS = Selenium::Remote::WDKeys::KEYS();
    my $fname = $driver->find_element('fname', 'id');
    $fname->send_keys('Hello');
    # Select all and delete with keyboard
    $fname->send_keys($KEYS->{backspace});
    my $val = $fname->get_value();
    is($val, 'Hell', 'Backspace key removed last char');

    $driver->quit();
};

# ==============================
# JavaScript Execution
# ==============================

subtest "execute_script" => sub {
    my $driver = Selenium::Remote::Driver->new(
        browser_name => 'chrome',
        auto_close   => 0,
    );
    $driver->get(file_url('index.html'));

    my $title = $driver->execute_script('return document.title');
    is($title, 'Test Page', 'execute_script returns value');

    my $sum = $driver->execute_script('return arguments[0] + arguments[1]', 3, 4);
    is($sum, 7, 'execute_script with arguments');

    # With WebElement argument
    my $el = $driver->find_element('heading', 'id');
    my $text = $driver->execute_script('return arguments[0].textContent', $el);
    is($text, 'Test Heading', 'execute_script with WebElement arg');

    $driver->quit();
};

# ==============================
# Window Management
# ==============================

subtest "Window handles" => sub {
    my $driver = Selenium::Remote::Driver->new(
        browser_name => 'chrome',
        auto_close   => 0,
    );
    $driver->get(file_url('links.html'));

    my $handle = $driver->get_current_window_handle();
    ok($handle, 'Got current window handle');

    my $handles = $driver->get_window_handles();
    is(scalar @$handles, 1, 'One window initially');

    $driver->quit();
};

subtest "Window size" => sub {
    my $driver = Selenium::Remote::Driver->new(
        browser_name => 'chrome',
        auto_close   => 0,
    );

    $driver->set_window_size(600, 800);
    my $size = $driver->get_window_size();
    is($size->{width}, 800, 'Width set correctly');
    is($size->{height}, 600, 'Height set correctly');

    $driver->maximize_window();
    $size = $driver->get_window_size();
    ok($size->{width} >= 1024, 'Maximized width is large');

    $driver->quit();
};

# ==============================
# Cookies
# ==============================

subtest "Cookie management" => sub {
    my $driver = Selenium::Remote::Driver->new(
        browser_name => 'chrome',
        auto_close   => 0,
    );
    # Navigate to a real page (cookies need a URL context)
    $driver->get(file_url('index.html'));

    $driver->delete_all_cookies();
    my $cookies = $driver->get_all_cookies();
    is(scalar @$cookies, 0, 'No cookies after delete_all');

    $driver->quit();
};

# ==============================
# Frames
# ==============================

subtest "Frame switching" => sub {
    my $driver = Selenium::Remote::Driver->new(
        browser_name => 'chrome',
        auto_close   => 0,
    );
    $driver->get(file_url('frames.html'));

    # Switch to frame by name
    $driver->switch_to_frame('first-frame');
    my $heading = $driver->find_element('frame-heading', 'id');
    is($heading->get_text(), 'Frame 1 Content', 'Found element in frame');

    # Switch back to main
    $driver->switch_to_frame(undef);
    my $main_heading = $driver->find_element('//h1', 'xpath');
    is($main_heading->get_text(), 'Frames Test', 'Back to main frame');

    # Switch by index
    $driver->switch_to_frame(0);
    $heading = $driver->find_element('frame-heading', 'id');
    like($heading->get_text(), qr/Frame \d Content/, 'Found element in frame by index');

    # Parent frame
    $driver->switch_to_parent_frame();
    $main_heading = $driver->find_element('//h1', 'xpath');
    is($main_heading->get_text(), 'Frames Test', 'Parent frame returns to main');

    $driver->quit();
};

# ==============================
# Screenshots
# ==============================

subtest "Screenshots" => sub {
    my $driver = Selenium::Remote::Driver->new(
        browser_name => 'chrome',
        auto_close   => 0,
    );
    $driver->get(file_url('index.html'));

    my $data = $driver->screenshot();
    ok($data, 'screenshot returns data');
    ok(length($data) > 100, 'screenshot data has substantial length');

    my $tmpfile = '/tmp/selenium_compat_test_screenshot.png';
    $driver->capture_screenshot($tmpfile);
    ok(-f $tmpfile, 'capture_screenshot creates file');
    unlink $tmpfile;

    $driver->quit();
};

# ==============================
# Timeouts
# ==============================

subtest "Timeouts" => sub {
    my $driver = Selenium::Remote::Driver->new(
        browser_name => 'chrome',
        auto_close   => 0,
    );

    $driver->set_timeout('implicit', 5000);
    my $timeouts = $driver->get_timeouts();
    is($timeouts->{implicit}, 5000, 'Implicit timeout set');

    $driver->set_implicit_wait_timeout(0);
    $timeouts = $driver->get_timeouts();
    is($timeouts->{implicit}, 0, 'Implicit timeout reset');

    $driver->quit();
};

# ==============================
# Alerts (basic)
# ==============================

subtest "Alert handling" => sub {
    my $driver = Selenium::Remote::Driver->new(
        browser_name => 'chrome',
        auto_close   => 0,
    );
    $driver->get(file_url('alerts.html'));

    # Arm the dialog listener BEFORE the click that triggers the dialog.
    # Playwright fires dialogs as events that must be handled before the
    # triggering action returns.
    $driver->arm_dialog_listener();

    my $btn = $driver->find_element('alert-btn', 'id');
    $btn->click();

    my $text = $driver->get_alert_text();
    is($text, 'Hello Alert', 'Got alert text');
    $driver->accept_alert();
    pass('Alert accepted');

    $driver->quit();
};

# ==============================
# Waiter
# ==============================

subtest "wait_until" => sub {
    require Playwright::SeleniumMigrator::Waiter;
    my $count = 0;
    my $result = Selenium::Waiter::wait_until(sub { ++$count >= 3 }, timeout => 5);
    ok($result, 'wait_until succeeded');

    my $fail = Selenium::Waiter::wait_until(sub { 0 }, timeout => 1, interval => 0.1);
    ok(!$fail, 'wait_until returns false on timeout');
};

# ==============================
# Miscellaneous
# ==============================

subtest "Misc driver methods" => sub {
    my $driver = Selenium::Remote::Driver->new(
        browser_name => 'chrome',
        auto_close   => 0,
    );
    $driver->get(file_url('index.html'));

    ok($driver->has_javascript(), 'has_javascript');

    my $ua = $driver->get_user_agent();
    ok($ua, 'get_user_agent returns value');
    like($ua, qr/Mozilla|Chrome|HeadlessChrome/, 'User agent looks valid');

    my $path = $driver->get_path();
    like($path, qr/index\.html/, 'get_path returns pathname');

    $driver->quit();
};

done_testing();
