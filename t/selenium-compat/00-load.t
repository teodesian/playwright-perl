use strict;
use warnings;
use Test2::V0;

# Load the migrator module
ok(eval { require Playwright::SeleniumMigrator; Playwright::SeleniumMigrator->import(); 1 },
    'Playwright::SeleniumMigrator loads') or diag $@;

# Verify that the Selenium packages are now defined
ok(Selenium::Remote::Driver->can('new'), 'Selenium::Remote::Driver->new is available');
ok(Selenium::Remote::Driver->can('get'), 'Selenium::Remote::Driver->get is available');
ok(Selenium::Remote::Driver->can('find_element'), 'Selenium::Remote::Driver->find_element is available');
ok(Selenium::Remote::Driver->can('find_elements'), 'Selenium::Remote::Driver->find_elements is available');
ok(Selenium::Remote::Driver->can('quit'), 'Selenium::Remote::Driver->quit is available');
ok(Selenium::Remote::Driver->can('execute_script'), 'Selenium::Remote::Driver->execute_script is available');
ok(Selenium::Remote::Driver->can('get_current_url'), 'Selenium::Remote::Driver->get_current_url is available');
ok(Selenium::Remote::Driver->can('get_title'), 'Selenium::Remote::Driver->get_title is available');
ok(Selenium::Remote::Driver->can('go_back'), 'Selenium::Remote::Driver->go_back is available');
ok(Selenium::Remote::Driver->can('screenshot'), 'Selenium::Remote::Driver->screenshot is available');

ok(Selenium::Remote::WebElement->can('new'), 'Selenium::Remote::WebElement->new is available');
ok(Selenium::Remote::WebElement->can('click'), 'Selenium::Remote::WebElement->click is available');
ok(Selenium::Remote::WebElement->can('send_keys'), 'Selenium::Remote::WebElement->send_keys is available');
ok(Selenium::Remote::WebElement->can('get_text'), 'Selenium::Remote::WebElement->get_text is available');
ok(Selenium::Remote::WebElement->can('get_attribute'), 'Selenium::Remote::WebElement->get_attribute is available');
ok(Selenium::Remote::WebElement->can('is_displayed'), 'Selenium::Remote::WebElement->is_displayed is available');
ok(Selenium::Remote::WebElement->can('is_enabled'), 'Selenium::Remote::WebElement->is_enabled is available');
ok(Selenium::Remote::WebElement->can('clear'), 'Selenium::Remote::WebElement->clear is available');
ok(Selenium::Remote::WebElement->can('get_tag_name'), 'Selenium::Remote::WebElement->get_tag_name is available');

# WDKeys - already loaded by the migrator
my $keys = Selenium::Remote::WDKeys::KEYS();
ok(ref $keys eq 'HASH', 'KEYS returns a hashref');
ok(exists $keys->{enter}, 'KEYS has enter key');
ok(exists $keys->{tab}, 'KEYS has tab key');
ok(exists $keys->{backspace}, 'KEYS has backspace key');
ok(exists $keys->{space}, 'KEYS has space key');

# Waiter - already loaded by the migrator
ok(Selenium::Waiter->can('wait_until'), 'Selenium::Waiter->wait_until is available');

# SeleniumMigrator is detectable via %INC
ok($INC{'Playwright/SeleniumMigrator.pm'}, 'SeleniumMigrator is in %INC');

done_testing();
