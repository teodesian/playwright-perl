package Playwright::SeleniumMigrator;

use strict;
use warnings;

use v5.28;

#ABSTRACT: Selenium::Remote::Driver compatibility layer for Playwright

no warnings 'experimental';
use feature qw{signatures};

use Carp qw{confess};

# Load sub-modules.  The ':dropin' tag on Driver causes Selenium::Remote::Driver
# and Selenium::Remote::WebElement to become aliases for the Playwright-backed
# implementations, so existing test suites can run unmodified.
use Playwright::SeleniumMigrator::Driver ':dropin';
use Playwright::SeleniumMigrator::WebElement;
use Playwright::SeleniumMigrator::WDKeys;
use Playwright::SeleniumMigrator::Waiter;

=head1 SYNOPSIS

    # Replace:
    #   use Selenium::Remote::Driver;
    # With:
    use Playwright::SeleniumMigrator;

    my $driver = Selenium::Remote::Driver->new(browser_name => 'chrome');
    $driver->get('http://example.com');
    my $element = $driver->find_element('h1', 'tag_name');
    print $element->get_text();
    $driver->quit();

=head1 DESCRIPTION

Playwright::SeleniumMigrator provides a drop-in compatibility layer that allows
existing L<Selenium::Remote::Driver> test suites to run against Playwright
without code changes.

Simply replace your C<use Selenium::Remote::Driver> statement with
C<use Playwright::SeleniumMigrator>.

=head2 Concept mapping

=over 4

=item * Selenium B<window> == Playwright B<Page>

=item * Window handles returned by C<get_current_window_handle> /
C<get_window_handles> are the GUIDs of the underlying Playwright Page objects.

=item * Selenium B<session> == Playwright B<Browser>

=back

=head2 Alert / dialog handling

Unlike Selenium (which queues dialogs asynchronously), Playwright fires dialogs
as events that must be handled before the triggering action returns.  Call
C<< $driver->arm_dialog_listener() >> B<before> the click or action that will
raise a dialog:

    $driver->arm_dialog_listener();
    $driver->find_element('#ok-btn', 'id')->click();
    my $text = $driver->get_alert_text();
    $driver->accept_alert();

=head2 Advanced usage: named package

To use the Playwright-backed driver under its own name without polluting the
C<Selenium::Remote::Driver> namespace:

    use Selenium::Remote::Driver::Playwright;
    my $driver = Selenium::Remote::Driver::Playwright->new(browser_name => 'chrome');

=cut

1;
