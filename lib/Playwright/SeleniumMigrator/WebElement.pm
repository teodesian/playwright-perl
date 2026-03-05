package Playwright::SeleniumMigrator::WebElement;

# Loader shim - actual implementation is in Selenium::Remote::WebElement::Playwright.
# Nothing needed here; the package is just a load target.

package Selenium::Remote::WebElement::Playwright;

# In :dropin mode, Driver.pm's import() adds this package to
# @Selenium::Remote::WebElement::ISA (S::R::WE -> S::R::WE::Playwright).
# Adding S::R::WE back to our own @ISA would create a cycle, so we only
# inherit from it when we are NOT already in S::R::WE's @ISA.
our @ISA;
BEGIN {
    unless (grep { $_ eq 'Selenium::Remote::WebElement::Playwright' }
                @Selenium::Remote::WebElement::ISA) {
        @ISA = ('Selenium::Remote::WebElement');
    }
}

use strict;
use warnings;

use v5.28;

use Carp qw{confess};

no warnings 'experimental';
use feature qw{signatures};

use Playwright::SeleniumMigrator::WDKeys;

sub new ($class, %opts) {
    confess "Missing _driver"  unless $opts{_driver};
    confess "Missing _element" unless $opts{_element};
    # Use the underlying Playwright element's GUID as the WebElement ID.
    confess "_element must have a guid" unless $opts{_element}{guid};

    return bless {
        _driver  => $opts{_driver},
        _element => $opts{_element},
        _id      => $opts{_element}{guid},
    }, $class;
}

# ---- Accessors ----

sub id     ($self) { return $self->{_id} }
sub driver ($self) { return $self->{_driver} }

# ---- Interaction ----

sub click ($self, %opts) {
    $self->{_element}->click(\%opts);
    return;
}

sub submit ($self) {
    my $page = $self->{_driver}{_page};
    $page->evaluate(
        'var el = arguments[0]; if (el.form) { el.form.submit() } else if (el.submit) { el.submit() } else { throw new Error("Element has no form to submit") }',
        $self->{_element}
    );
    return;
}

sub send_keys ($self, @keys) {
    my $page = $self->{_driver}{_page};
    my $eh   = $self->{_element};

    # Click to focus (more reliable than focus() and avoids handle disposal
    # issues that arise with elementHandle.type()).
    $eh->click();

    for my $key_string (@keys) {
        my @chars = split //, $key_string;
        my $buffer = '';

        for my $char (@chars) {
            my $ord = ord($char);
            # Unicode PUA codepoints (U+E000–U+F8FF) are Selenium special keys
            if ($ord >= 0xE000 && $ord <= 0xF8FF) {
                if (length $buffer) {
                    $page->keyboard->type($buffer);
                    $buffer = '';
                }
                my $pw_key = $Selenium::Remote::WDKeys::UNICODE_TO_PLAYWRIGHT{$char};
                if (defined $pw_key && length $pw_key) {
                    $page->keyboard->press($pw_key);
                }
                # U+E000 null key is a no-op
            }
            else {
                $buffer .= $char;
            }
        }

        if (length $buffer) {
            $page->keyboard->type($buffer);
        }
    }
    return;
}

sub clear ($self) {
    $self->{_element}->fill('');
    return;
}

# ---- Text & Content ----

sub get_text ($self) {
    return $self->{_element}->innerText();
}

sub get_attribute ($self, $name) {
    return $self->{_element}->getAttribute($name);
}

sub get_property ($self, $name) {
    my $page = $self->{_driver}{_page};
    return $page->evaluate("return arguments[0]['$name']", $self->{_element});
}

sub get_value ($self) {
    return $self->{_element}->inputValue();
}

sub get_tag_name ($self) {
    my $page = $self->{_driver}{_page};
    return $page->evaluate('return arguments[0].tagName.toLowerCase()', $self->{_element});
}

sub get_css_attribute ($self, $prop) {
    my $page = $self->{_driver}{_page};
    return $page->evaluate(
        "return window.getComputedStyle(arguments[0]).getPropertyValue('$prop')",
        $self->{_element}
    );
}

# ---- State ----

sub is_displayed ($self) {
    return $self->{_element}->isVisible() ? 1 : 0;
}

sub is_hidden ($self) {
    return $self->{_element}->isHidden() ? 1 : 0;
}

sub is_enabled ($self) {
    return $self->{_element}->isEnabled() ? 1 : 0;
}

sub is_selected ($self) {
    # isChecked() works for checkboxes and radio buttons.
    # For <option> elements, check the .selected property.
    my $tag = $self->get_tag_name();
    if ($tag eq 'option') {
        my $page = $self->{_driver}{_page};
        return $page->evaluate('return arguments[0].selected', $self->{_element}) ? 1 : 0;
    }
    return $self->{_element}->isChecked() ? 1 : 0;
}

sub set_selected ($self) {
    my $tag = $self->get_tag_name();
    if ($tag eq 'option') {
        my $page = $self->{_driver}{_page};
        $page->evaluate('arguments[0].selected = true', $self->{_element});
    }
    elsif (!$self->is_selected()) {
        $self->{_element}->check();
    }
    return;
}

sub toggle ($self) {
    if ($self->is_selected()) {
        $self->{_element}->uncheck();
    }
    else {
        $self->{_element}->check();
    }
    return;
}

# ---- Position & Size ----

sub get_size ($self) {
    my $box = $self->{_element}->boundingBox();
    return {
        width  => $box->{width},
        height => $box->{height},
    };
}

sub get_element_location ($self) {
    my $box = $self->{_element}->boundingBox();
    return {
        x => $box->{x},
        y => $box->{y},
    };
}

sub get_element_rect ($self) {
    return $self->{_element}->boundingBox();
}

sub get_element_location_in_view ($self) {
    $self->{_element}->scrollIntoViewIfNeeded();
    return $self->get_element_location();
}

# ---- Screenshots ----

sub screenshot ($self, $scroll = 0) {
    $self->{_element}->scrollIntoViewIfNeeded() if $scroll;
    return $self->{_element}->screenshot();
}

sub capture_screenshot ($self, $filename, $scroll = 0) {
    $self->{_element}->scrollIntoViewIfNeeded() if $scroll;
    $self->{_element}->screenshot({ path => $filename });
    return 1;
}

# ---- Child Elements ----

sub child ($self, $locator, $strategy = undef) {
    return $self->{_driver}->find_child_element($self, $locator, $strategy);
}

sub children ($self, $locator, $strategy = undef) {
    return $self->{_driver}->find_child_elements($self, $locator, $strategy);
}

# ---- JavaScript ----

sub execute_script ($self, $script, @args) {
    # Prepend self as the first argument
    unshift @args, $self;
    return $self->{_driver}->execute_script($script, @args);
}

sub execute_async_script ($self, $script, @args) {
    unshift @args, $self;
    return $self->{_driver}->execute_async_script($script, @args);
}

# ---- Drag & Drop ----

sub drag ($self, $target) {
    my $src_box = $self->{_element}->boundingBox();
    my $dst_box = $target->{_element}->boundingBox();

    my $page = $self->{_driver}{_page};
    my $sx = $src_box->{x} + $src_box->{width}  / 2;
    my $sy = $src_box->{y} + $src_box->{height} / 2;
    my $dx = $dst_box->{x} + $dst_box->{width}  / 2;
    my $dy = $dst_box->{y} + $dst_box->{height} / 2;

    $page->mouse->move($sx, $sy);
    $page->mouse->down();
    $page->mouse->move($dx, $dy);
    $page->mouse->up();
    return;
}

1;
