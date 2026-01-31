package Playwright::SeleniumMigrator;

use strict;
use warnings;

use v5.28;

#ABSTRACT: Selenium::Remote::Driver compatibility layer for Playwright

no warnings 'experimental';
use feature qw{signatures};

use Carp qw{confess};

# Refuse to load if Selenium::Remote::Driver is already in scope.
# If it is, we'd be redefining some but not all of the module space,
# which would lead to confusing partial-override bugs.
BEGIN {
    if ($INC{'Selenium/Remote/Driver.pm'}) {
        confess "Selenium::Remote::Driver is already loaded. "
              . "Playwright::SeleniumMigrator must be loaded INSTEAD of "
              . "Selenium::Remote::Driver, not alongside it.";
    }
}

# Load our sub-modules which define the Selenium::* packages.
# Playwright itself is loaded lazily at Driver->new() time so that
# this module can be loaded even without the generated Playwright modules.
use Playwright::SeleniumMigrator::Driver;
use Playwright::SeleniumMigrator::WebElement;
use Playwright::SeleniumMigrator::WDKeys;
use Playwright::SeleniumMigrator::Waiter;

=head1 SYNOPSIS

    # Instead of:
    #   use Selenium::Remote::Driver;
    # Use:
    use Playwright::SeleniumMigrator;

    my $driver = Selenium::Remote::Driver->new(browser_name => 'chrome');
    $driver->get('http://example.com');
    my $element = $driver->find_element('h1', 'tag_name');
    print $element->get_text();
    $driver->quit();

=head1 DESCRIPTION

Playwright::SeleniumMigrator provides a drop-in compatibility layer that allows
existing Selenium::Remote::Driver test suites to run against Playwright without
code changes. Simply replace your C<use Selenium::Remote::Driver> statement with
C<use Playwright::SeleniumMigrator>.

This module defines the C<Selenium::Remote::Driver>, C<Selenium::Remote::WebElement>,
C<Selenium::Remote::WDKeys>, and C<Selenium::Waiter> packages, backed by Playwright
method calls.

=cut

1;
