package Playwright::Util;

use strict;
use warnings;

use v5.28;

use JSON::MaybeXS();
use Carp qw{confess};
use Sereal::Encoder;
use Sereal::Decoder;
use File::Temp;
use POSIX();

#ABSTRACT: Common utility functions for the Playwright module

no warnings 'experimental';
use feature qw{signatures};

use constant IS_WIN => $^O eq 'MSWin32';

=head2 request(STRING method, STRING url, STRING host, INTEGER port, LWP::UserAgent ua, HASH args) = HASH

De-duplicates request logic in the Playwright Modules.

=cut

sub request ( $method,$url, $host, $port, $ua, %args ) {
    my $fullurl = "http://$host:$port/$url";

    # Handle passing Playwright elements as arguments
    if (ref $args{args} eq 'ARRAY') {
        @{$args{args}} = map {
            my $transformed = $_;
            if (ref($_) eq 'Playwright::ElementHandle' ) {
                $transformed = { uuid => $_->{guid} }
            }
            $transformed;
        } @{$args{args}};
    }

    my $request = HTTP::Request->new( $method, $fullurl );
    $request->header( 'Content-type' => 'application/json' );
    $request->content( JSON::MaybeXS::encode_json( \%args ) );
    my $response = $ua->request($request);
    my $content  = $response->decoded_content();

    # If we get this kind of response the server failed to come up :(
    die "playwright server failed to spawn!" if $content =~ m/^Can't connect to/;

    my $decoded  = JSON::MaybeXS::decode_json($content);
    my $msg      = $decoded->{message};

    confess($msg) if $decoded->{error};

    return $msg;
}

sub arr2hash ($array,$primary_key,$callback='') {
    my $inside_out = {};
    @$inside_out{map { $callback ? $callback->($_->{$primary_key}) : $_->{$primary_key} } @$array} = @$array;
    return $inside_out;
}

# Serialize a subprocess because NOTHING ON CPAN DOES THIS GRRRRR
sub async ($subroutine) {
    # The fork would result in the tmpdir getting whacked when it terminates.
    my $fh = File::Temp->new();
    my $pid = fork() // die "Could not fork";
    _child($fh->filename, $subroutine) unless $pid;
    return { pid => $pid, file => $fh };
}

sub _child ($filename,$subroutine) {
    Sereal::Encoder->encode_to_file($filename,$subroutine->());
    # Prevent destructors from firing due to exiting instantly...unless we are on windows, where they won't.
    POSIX::_exit(0) unless IS_WIN;
    exit 0;
}

sub await ($to_wait) {
    waitpid($to_wait->{pid},0);
    confess("Timed out while waiting for event.") unless -f $to_wait->{file}->filename && -s _;
    return Sereal::Decoder->decode_from_file($to_wait->{file}->filename);
}

1;
