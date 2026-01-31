package Selenium::Remote::Driver;

use strict;
use warnings;

use v5.28;

use Carp qw{confess carp};
use Data::Dumper;

no warnings 'experimental';
use feature qw{signatures};

use Playwright::SeleniumMigrator::WDKeys;

# Playwright is loaded lazily at new() time.
# We skip Playwright's BEGIN block (_check_node) and let it run
# during new() instead, since the server binary may not be in PATH
# at compile time.
my $_playwright_loaded = 0;
sub _ensure_playwright {
    return if $_playwright_loaded;
    if (!$INC{'Playwright.pm'}) {
        no warnings qw{redefine once};
        $Playwright::SKIP_BEGIN = 1;
        require Playwright;
        Playwright::_check_node();
    }
    $_playwright_loaded = 1;
}

my $_handle_counter = 0;

sub _generate_handle {
    return 'CDwindow-' . sprintf('%08X', ++$_handle_counter) . '-' . int(rand(65536));
}

=head1 NAME

Selenium::Remote::Driver - Compatibility shim backed by Playwright

=head1 CONSTRUCTOR

=head2 new(%options)

Creates a new driver instance backed by Playwright.

Supported options: browser_name, base_url, default_finder, auto_close,
inner_window_size, javascript, headless.

Selenium-specific options (remote_server_addr, port, session_id, etc.) are
accepted but ignored with a warning.

=cut

sub new ( $class, %opts ) {
    _ensure_playwright();

    my $browser_name = delete $opts{browser_name} // 'firefox';
    my $base_url     = delete $opts{base_url}     // '';
    my $default_finder = delete $opts{default_finder} // 'xpath';
    my $auto_close   = exists $opts{auto_close} ? delete $opts{auto_close} : 1;
    my $inner_window_size = delete $opts{inner_window_size};
    my $headless     = delete $opts{headless}     // 1;

    # Accept but ignore Selenium-specific options
    for my $ignored (qw{remote_server_addr port session_id version platform
                        accept_ssl_certs javascript extra_capabilities
                        firefox_profile pageLoadStrategy error_handler
                        webelement_class ua proxy debug}) {
        if (exists $opts{$ignored}) {
            carp "Playwright::SeleniumMigrator: ignoring Selenium option '$ignored'"
                unless $ignored eq 'javascript' || $ignored eq 'debug';
            delete $opts{$ignored};
        }
    }

    my %browser_map = (
        chrome         => 'chrome',
        googlechrome   => 'chrome',
        firefox        => 'firefox',
        MicrosoftEdge  => 'chrome',
        safari         => 'webkit',
        webkit         => 'webkit',
    );
    my $pw_type = $browser_map{ lc($browser_name) } // $browser_map{$browser_name} // 'chrome';

    my $pw      = Playwright->new();
    my $browser = $pw->launch(headless => $headless, type => $pw_type);
    my $page    = $browser->newPage();
    my ($context) = @{ $browser->contexts() };

    my $handle = _generate_handle();

    my $self = bless {
        _pw              => $pw,
        _browser         => $browser,
        _page            => $page,
        _context         => $context,
        _pages           => { $handle => $page },
        _current_handle  => $handle,
        _frame           => undef,
        _frame_stack     => [],
        _base_url        => $base_url,
        _default_finder  => $default_finder,
        _implicit_wait   => 0,
        _script_timeout  => 30000,
        _page_load_timeout => 300000,
        _auto_close      => $auto_close,
        _dialog_queue    => [],
        _dialog_listener => 0,
        _browser_name    => $browser_name,
    }, $class;

    if ($inner_window_size) {
        my ($h, $w) = @$inner_window_size;
        $page->setViewportSize({ width => int($w), height => int($h) });
    }

    return $self;
}

sub _ensure_dialog_listener ($self) {
    # Register auto-accept handler once per page
    if (!$self->{_dialog_on_registered}) {
        eval {
            $self->{_page}->on('dialog', 'dialog', 'dialog.accept()');
        };
        $self->{_dialog_on_registered} = 1;
    }

    # Arm waitForEvent if not already armed
    return if $self->{_dialog_listener};
    eval {
        $self->{_dialog_promise} = $self->{_page}->waitForEvent('dialog');
    };
    $self->{_dialog_listener} = 1;
}

# ---- Navigation ----

sub get ($self, $url) {
    $url = $self->_resolve_url($url);
    my $target = $self->{_page};
    $target->goto($url);
    return;
}

sub navigate ($self, $url) { return $self->get($url) }

sub get_current_url ($self) {
    return $self->{_page}->url();
}

sub get_title ($self) {
    return $self->{_page}->title();
}

sub go_back ($self) {
    $self->{_page}->goBack();
    return;
}

sub go_forward ($self) {
    $self->{_page}->goForward();
    return;
}

sub refresh ($self) {
    $self->{_page}->reload();
    return;
}

sub get_page_source ($self) {
    return $self->{_page}->content();
}

# ---- Element Finding ----

sub _resolve_selector ($self, $locator, $strategy = undef) {
    $strategy //= $self->{_default_finder};

    # Normalize strategy names
    my %aliases = (
        css_selector => 'css',
        'class name' => 'class_name',
        'link text'  => 'link_text',
        class        => 'class_name',
        link         => 'link_text',
    );
    $strategy = $aliases{$strategy} // $strategy;

    my %map = (
        css             => sub { $locator },
        id              => sub { "#$locator" },
        name            => sub { qq{[name="$locator"]} },
        class_name      => sub { ".$locator" },
        tag_name        => sub { $locator },
        link_text       => sub { qq{xpath=//a[normalize-space(.)="$locator"]} },
        partial_link_text => sub { qq{xpath=//a[contains(normalize-space(.),"$locator")]} },
        xpath           => sub { "xpath=$locator" },
    );

    my $resolver = $map{$strategy}
        or confess "Unknown locator strategy: '$strategy'";
    return $resolver->();
}

sub _resolve_url ($self, $url) {
    if ($self->{_base_url} && $url =~ m{^/}) {
        return $self->{_base_url} . $url;
    }
    return $url;
}

sub _target ($self) {
    return $self->{_frame} // $self->{_page};
}

sub find_element ($self, $locator, $strategy = undef) {
    my $selector = $self->_resolve_selector($locator, $strategy);
    my $target = $self->_target();

    my $element;
    if ($self->{_implicit_wait} > 0) {
        $self->{_pw}->pusht($target, $self->{_implicit_wait});
        eval {
            $element = $self->{_pw}->try_until($target, 'select', $selector);
        };
        my $err = $@;
        $self->{_pw}->popt($target);
        confess "Element not found using strategy '$strategy' and locator '$locator'" if $err || !$element;
    }
    else {
        $element = $target->select($selector);
    }

    confess "Element not found using strategy '$strategy' and locator '$locator'"
        unless $element;

    return Selenium::Remote::WebElement->new(
        _driver  => $self,
        _element => $element,
    );
}

sub find_elements ($self, $locator, $strategy = undef) {
    my $selector = $self->_resolve_selector($locator, $strategy);
    my $target = $self->_target();

    my @elements;
    if ($self->{_implicit_wait} > 0) {
        $self->{_pw}->pusht($target, $self->{_implicit_wait});
        eval {
            @elements = @{ $self->{_pw}->try_until($target, 'selectMulti', $selector) // [] };
        };
        $self->{_pw}->popt($target);
    }
    else {
        my $result = $target->selectMulti($selector);
        @elements = @{ $result // [] };
    }

    return map {
        Selenium::Remote::WebElement->new(
            _driver  => $self,
            _element => $_,
        )
    } @elements;
}

sub find_child_element ($self, $parent, $locator, $strategy = undef) {
    my $selector = $self->_resolve_selector($locator, $strategy);
    my $eh = $parent->{_element};

    my $element = $eh->select($selector);
    confess "Child element not found using strategy '$strategy' and locator '$locator'"
        unless $element;

    return Selenium::Remote::WebElement->new(
        _driver  => $self,
        _element => $element,
    );
}

sub find_child_elements ($self, $parent, $locator, $strategy = undef) {
    my $selector = $self->_resolve_selector($locator, $strategy);
    my $eh = $parent->{_element};

    my $result = $eh->selectMulti($selector);
    my @elements = @{ $result // [] };

    return map {
        Selenium::Remote::WebElement->new(
            _driver  => $self,
            _element => $_,
        )
    } @elements;
}

sub get_active_element ($self) {
    my $handle = $self->{_page}->evaluateHandle('() => document.activeElement');
    return unless $handle;
    return Selenium::Remote::WebElement->new(
        _driver  => $self,
        _element => $handle,
    );
}

# Convenience finders
sub find_element_by_id              ($self, $loc) { return $self->find_element($loc, 'id') }
sub find_element_by_class           ($self, $loc) { return $self->find_element($loc, 'class_name') }
sub find_element_by_class_name      ($self, $loc) { return $self->find_element($loc, 'class_name') }
sub find_element_by_css             ($self, $loc) { return $self->find_element($loc, 'css') }
sub find_element_by_link            ($self, $loc) { return $self->find_element($loc, 'link_text') }
sub find_element_by_link_text       ($self, $loc) { return $self->find_element($loc, 'link_text') }
sub find_element_by_partial_link_text ($self, $loc) { return $self->find_element($loc, 'partial_link_text') }
sub find_element_by_name            ($self, $loc) { return $self->find_element($loc, 'name') }
sub find_element_by_tag_name        ($self, $loc) { return $self->find_element($loc, 'tag_name') }
sub find_element_by_xpath           ($self, $loc) { return $self->find_element($loc, 'xpath') }

sub find_elements_by_id              ($self, $loc) { return $self->find_elements($loc, 'id') }
sub find_elements_by_class           ($self, $loc) { return $self->find_elements($loc, 'class_name') }
sub find_elements_by_class_name      ($self, $loc) { return $self->find_elements($loc, 'class_name') }
sub find_elements_by_css             ($self, $loc) { return $self->find_elements($loc, 'css') }
sub find_elements_by_link            ($self, $loc) { return $self->find_elements($loc, 'link_text') }
sub find_elements_by_link_text       ($self, $loc) { return $self->find_elements($loc, 'link_text') }
sub find_elements_by_partial_link_text ($self, $loc) { return $self->find_elements($loc, 'partial_link_text') }
sub find_elements_by_name            ($self, $loc) { return $self->find_elements($loc, 'name') }
sub find_elements_by_tag_name        ($self, $loc) { return $self->find_elements($loc, 'tag_name') }
sub find_elements_by_xpath           ($self, $loc) { return $self->find_elements($loc, 'xpath') }

# ---- JavaScript Execution ----

sub execute_script ($self, $script, @args) {
    my $target = $self->_target();

    # Unwrap WebElement args to ElementHandle objects
    @args = map {
        (ref $_ && ref $_ eq 'Selenium::Remote::WebElement') ? $_->{_element} : $_
    } @args;

    if (@args == 0) {
        return $target->evaluate($script);
    }
    elsif (@args == 1) {
        return $target->evaluate($script, $args[0]);
    }
    else {
        # Playwright evaluate only accepts a single argument.
        # Wrap multiple args in an array and rewrite the script to
        # use them as arguments to the inner function.
        my $wrapper = "var __pw_args = arguments[0]; return (function() { $script }).apply(null, __pw_args);";
        return $target->evaluate($wrapper, \@args);
    }
}

sub execute_async_script ($self, $script, @args) {
    my $target = $self->_target();

    @args = map {
        (ref $_ && ref $_ eq 'Selenium::Remote::WebElement') ? $_->{_element} : $_
    } @args;

    # Selenium's async scripts receive a callback as the last argument.
    # Wrap the user script in a Promise that resolves via that callback.
    my $async_wrapper = qq{
        return new Promise((resolve, reject) => {
            try {
                var __args = [...arguments];
                var __callback = function(result) { resolve(result); };
                __args.push(__callback);
                (function() { $script }).apply(null, __args);
            } catch(e) { reject(e); }
        });
    };

    return $target->evaluate($async_wrapper, @args);
}

# ---- Window Management ----

sub get_current_window_handle ($self) {
    return $self->{_current_handle};
}

sub get_window_handles ($self) {
    $self->_sync_pages();
    return [ keys %{ $self->{_pages} } ];
}

sub _sync_pages ($self) {
    my @live_pages = @{ $self->{_context}->pages() };

    # Build a set of known page GUIDs
    my %known_guids;
    for my $handle (keys %{ $self->{_pages} }) {
        my $page = $self->{_pages}{$handle};
        $known_guids{ $page->{guid} } = $handle if ref $page && $page->{guid};
    }

    # Add any new pages
    for my $page (@live_pages) {
        next if exists $known_guids{ $page->{guid} };
        my $handle = _generate_handle();
        $self->{_pages}{$handle} = $page;
    }

    # Remove closed pages
    my %live_guids = map { $_->{guid} => 1 } @live_pages;
    for my $handle (keys %{ $self->{_pages} }) {
        my $page = $self->{_pages}{$handle};
        if (ref $page && $page->{guid} && !$live_guids{ $page->{guid} }) {
            delete $self->{_pages}{$handle};
        }
    }
}

sub switch_to_window ($self, $handle_or_title) {
    $self->_sync_pages();

    # Try by handle first
    if (exists $self->{_pages}{$handle_or_title}) {
        $self->{_page} = $self->{_pages}{$handle_or_title};
        $self->{_current_handle} = $handle_or_title;
        $self->{_frame} = undef;
        $self->{_dialog_listener} = 0;
        $self->{_dialog_on_registered} = 0;
        return;
    }

    # Try by title
    for my $handle (keys %{ $self->{_pages} }) {
        my $page = $self->{_pages}{$handle};
        my $title = eval { $page->title() } // '';
        if ($title eq $handle_or_title) {
            $self->{_page} = $page;
            $self->{_current_handle} = $handle;
            $self->{_frame} = undef;
            $self->{_dialog_listener} = 0;
        $self->{_dialog_on_registered} = 0;
            return;
        }
    }

    confess "No window found with handle or title: '$handle_or_title'";
}

sub close ($self) { ## no critic (Subroutines::ProhibitBuiltinHomonyms)
    my $current = $self->{_current_handle};
    $self->{_page}->close();
    delete $self->{_pages}{$current};

    # Switch to first remaining page if any
    my @remaining = keys %{ $self->{_pages} };
    if (@remaining) {
        $self->{_current_handle} = $remaining[0];
        $self->{_page} = $self->{_pages}{ $remaining[0] };
        $self->{_frame} = undef;
        $self->{_dialog_listener} = 0;
        $self->{_dialog_on_registered} = 0;
    }
    return;
}

sub get_window_size ($self) {
    my $viewport = $self->{_page}->viewportSize();
    return {
        width  => $viewport->{width},
        height => $viewport->{height},
    };
}

sub set_window_size ($self, $height, $width) {
    $self->{_page}->setViewportSize({
        width  => int($width),
        height => int($height),
    });
    return;
}

sub get_window_position ($self) {
    return { x => 0, y => 0 };
}

sub set_window_position ($self, $x, $y) {
    # Playwright doesn't support window positioning in the same way
    return;
}

sub maximize_window ($self) {
    $self->{_page}->setViewportSize({ width => 1920, height => 1080 });
    return;
}

sub minimize_window ($self) {
    return;
}

sub fullscreen_window ($self) {
    $self->{_page}->setViewportSize({ width => 1920, height => 1080 });
    return;
}

# ---- Frame Management ----

sub switch_to_frame ($self, $id = undef) {
    if (!defined $id) {
        # Switch to default content (main frame)
        $self->{_frame} = undef;
        $self->{_frame_stack} = [];
        return;
    }

    my $page = $self->{_page};

    if (ref $id && ref $id eq 'Selenium::Remote::WebElement') {
        # Switch to frame by WebElement
        my $frame = $id->{_element}->contentFrame();
        confess "Element is not a frame" unless $frame;
        push @{ $self->{_frame_stack} }, $self->{_frame};
        $self->{_frame} = $frame;
        return;
    }

    if ($id =~ /^\d+$/) {
        # By index
        my @frames = @{ $page->frames() };
        # frames()[0] is always the main frame, so frame index 0 in Selenium
        # corresponds to the first child frame
        my @child_frames = grep {
            my $parent = eval { $_->parentFrame() };
            $parent && ($self->{_frame} ?
                ($parent->{guid} eq $self->{_frame}{guid}) :
                ($parent->{guid} eq $page->mainFrame()->{guid}))
        } @frames;

        confess "No frame at index $id" unless $id < scalar @child_frames;
        push @{ $self->{_frame_stack} }, $self->{_frame};
        $self->{_frame} = $child_frames[$id];
        return;
    }

    # By name or id attribute
    my $target = $self->_target();
    my $frame_el = eval {
        $target->select(qq{iframe[name="$id"], iframe#$id, frame[name="$id"], frame#$id})
    };

    confess "Frame not found: '$id'" unless $frame_el;

    my $frame = $frame_el->contentFrame();
    confess "Could not access frame content: '$id'" unless $frame;

    push @{ $self->{_frame_stack} }, $self->{_frame};
    $self->{_frame} = $frame;
    return;
}

sub switch_to_parent_frame ($self) {
    if (@{ $self->{_frame_stack} }) {
        $self->{_frame} = pop @{ $self->{_frame_stack} };
    }
    else {
        $self->{_frame} = undef;
    }
    return;
}

# ---- Cookies ----

sub get_all_cookies ($self) {
    my $cookies = $self->{_context}->cookies();
    return ref $cookies eq 'ARRAY' ? $cookies : [];
}

sub add_cookie ($self, %cookie) {
    # Handle positional args: name, value, path, domain, secure, expiry
    # Or hash args

    # Translate Selenium expiry -> Playwright expires
    if (exists $cookie{expiry}) {
        $cookie{expires} = delete $cookie{expiry};
    }

    # Playwright requires url or (domain + path)
    if (!$cookie{url} && !$cookie{domain}) {
        $cookie{url} = $self->{_page}->url();
    }

    $self->{_context}->addCookies([ \%cookie ]);
    return;
}

sub delete_all_cookies ($self) {
    $self->{_context}->clearCookies();
    return;
}

sub delete_cookie_named ($self, $name) {
    $self->{_context}->clearCookies({ name => $name });
    return;
}

sub get_cookie_named ($self, $name) {
    my $cookies = $self->get_all_cookies();
    for my $cookie (@$cookies) {
        return $cookie if $cookie->{name} eq $name;
    }
    return;
}

# ---- Alerts/Dialogs ----

sub _await_dialog ($self) {
    return $self->{_dialog} if $self->{_dialog};
    confess "No dialog listener armed. Did a click() happen before this call?"
        unless $self->{_dialog_promise};

    $self->{_dialog} = $self->{_pw}->await($self->{_dialog_promise});
    $self->{_dialog_promise} = undef;
    $self->{_dialog_listener} = 0;
    return $self->{_dialog};
}

sub get_alert_text ($self) {
    my $dialog = $self->_await_dialog();
    return $dialog->message();
}

sub accept_alert ($self) {
    # Dialog was already auto-accepted by the on() handler.
    # Just consume the captured dialog to reset state.
    my $dialog = $self->_await_dialog();
    $self->{_dialog} = undef;
    return;
}

sub dismiss_alert ($self) {
    # Note: with the auto-accept pattern, dismiss_alert is equivalent to
    # accept_alert. The dialog was already accepted by the on() handler
    # to prevent blocking. This is a known limitation.
    my $dialog = $self->_await_dialog();
    $self->{_dialog} = undef;
    return;
}

sub send_keys_to_alert ($self, $keys) {
    # Note: the dialog was already auto-accepted. For prompt dialogs,
    # the text cannot be sent after auto-accept. This is a known limitation.
    my $dialog = $self->_await_dialog();
    $self->{_dialog} = undef;
    return;
}

sub send_keys_to_prompt ($self, $keys) {
    return $self->send_keys_to_alert($keys);
}

sub send_keys_to_active_element ($self, @keys) {
    my $text = join('', @keys);
    $self->{_page}->keyboard->type($text);
    return;
}

# ---- Timeouts ----

sub set_timeout ($self, $type, $ms) {
    if ($type eq 'implicit') {
        $self->{_implicit_wait} = $ms;
    }
    elsif ($type eq 'page load') {
        $self->{_page_load_timeout} = $ms;
        $self->{_page}->setDefaultNavigationTimeout($ms);
    }
    elsif ($type eq 'script') {
        $self->{_script_timeout} = $ms;
    }
    return;
}

sub set_implicit_wait_timeout ($self, $ms) {
    $self->{_implicit_wait} = $ms;
    return;
}

sub set_async_script_timeout ($self, $ms) {
    $self->{_script_timeout} = $ms;
    return;
}

sub get_timeouts ($self) {
    return {
        implicit => $self->{_implicit_wait},
        'page load' => $self->{_page_load_timeout},
        script => $self->{_script_timeout},
    };
}

# ---- Screenshots ----

sub screenshot ($self) {
    # Selenium returns base64-encoded PNG data.
    # Playwright's screenshot() returns binary data via the server,
    # so save to a temp file and read+encode it.
    require File::Temp;
    require MIME::Base64;
    my $tmp = File::Temp->new(SUFFIX => '.png');
    my $path = $tmp->filename;
    $self->{_page}->screenshot({ path => $path });
    open my $fh, '<:raw', $path or confess "Cannot read screenshot: $!";
    local $/;
    my $data = <$fh>;
    CORE::close $fh;
    return MIME::Base64::encode_base64($data, '');
}

sub capture_screenshot ($self, $filename) {
    $self->{_page}->screenshot({ path => $filename });
    return 1;
}

# ---- Mouse Actions (driver-level) ----

sub click ($self, $button = 'left', $x = undef, $y = undef) {
    my %opts;
    $opts{button} = $button if $button && $button ne 'left';
    if (defined $x && defined $y) {
        $self->{_page}->mouse->click($x, $y, \%opts);
    }
    return;
}

sub double_click ($self) {
    $self->{_page}->mouse->dblclick(0, 0);
    return;
}

sub button_down ($self, $button = 'left') {
    $self->{_page}->mouse->down({ button => $button });
    return;
}

sub button_up ($self, $button = 'left') {
    $self->{_page}->mouse->up({ button => $button });
    return;
}

sub move_to ($self, $element = undef, $x = undef, $y = undef) {
    if ($element) {
        my $box = $element->{_element}->boundingBox();
        my $cx = $box->{x} + $box->{width} / 2 + ($x // 0);
        my $cy = $box->{y} + $box->{height} / 2 + ($y // 0);
        $self->{_page}->mouse->move($cx, $cy);
    }
    elsif (defined $x && defined $y) {
        $self->{_page}->mouse->move($x, $y);
    }
    return;
}

sub mouse_move_to_location ($self, %opts) {
    my $x = $opts{x} // 0;
    my $y = $opts{y} // 0;
    if ($opts{element}) {
        return $self->move_to($opts{element}, $x, $y);
    }
    $self->{_page}->mouse->move($x, $y);
    return;
}

# ---- Miscellaneous ----

sub pause ($self, $seconds) {
    select(undef, undef, undef, $seconds);
    return;
}

sub get_capabilities ($self) {
    return {
        browserName => $self->{_browser_name},
        platformName => $^O,
    };
}

sub status ($self) {
    return { ready => 1 };
}

sub has_javascript ($self) { return 1 }

sub get_text ($self, $locator, $strategy = undef) {
    my $el = $self->find_element($locator, $strategy);
    return $el->get_text();
}

sub get_body ($self) {
    return $self->find_element('body', 'tag_name');
}

sub get_path ($self) {
    return $self->execute_script('return window.location.pathname');
}

sub get_user_agent ($self) {
    return $self->execute_script('return navigator.userAgent');
}

sub send_modifier ($self, $modifier, $direction) {
    my %mod_map = (
        Alt     => 'Alt',
        Control => 'Control',
        Shift   => 'Shift',
        Meta    => 'Meta',
    );
    my $key = $mod_map{$modifier} // $modifier;

    if ($direction eq 'down') {
        $self->{_page}->keyboard->down($key);
    }
    else {
        $self->{_page}->keyboard->up($key);
    }
    return;
}

# ---- Session/Lifecycle ----

sub quit ($self) {
    return if $self->{_quit_called};
    $self->{_quit_called} = 1;

    eval { $self->{_browser}->close() };
    eval { $self->{_pw}->quit() };

    $self->{_page}    = undef;
    $self->{_browser} = undef;
    $self->{_context} = undef;
    $self->{_pages}   = {};
    return;
}

sub DESTROY ($self) {
    $self->quit() if $self->{_auto_close} && !$self->{_quit_called};
}

sub debug_on  ($self) { return }
sub debug_off ($self) { return }

1;
