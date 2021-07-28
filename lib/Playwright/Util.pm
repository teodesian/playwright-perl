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

=head2 request(STRING method, STRING url, INTEGER port, LWP::UserAgent ua, HASH args) = HASH

De-duplicates request logic in the Playwright Modules.

=cut

sub request ( $method, $url, $port, $ua, %args ) {
    my $fullurl = "http://localhost:$port/$url";

    my $request = HTTP::Request->new( $method, $fullurl );
    $request->header( 'Content-type' => 'application/json' );
    $request->content( JSON::MaybeXS::encode_json( \%args ) );
    my $response = $ua->request($request);
    my $content  = $response->decoded_content();
    my $decoded  = JSON::MaybeXS::decode_json($content);
    my $msg      = $decoded->{message};

    confess($msg) if $decoded->{error};

    return $msg;
}

sub arr2hash ($array,$primary_key) {
    my $inside_out = {};
    @$inside_out{map { $_->{$primary_key} } @$array} = @$array;
    return $inside_out;
}

# Serialize a subprocess because NOTHING ON CPAN DOES THIS GRRRRR
sub async ($subroutine) {
    # The fork would result in the tmpdir getting whacked when it terminates.
    my (undef, $filename) = File::Temp::tempfile();
    my $pid = fork() // die "Could not fork";
    _child($filename, $subroutine) unless $pid;
    return { pid => $pid, file => $filename };
}

sub _child ($filename,$subroutine) {
    Sereal::Encoder->encode_to_file($filename,$subroutine->());
    # Prevent destructors from firing due to exiting instantly
    POSIX::_exit(0);
}

sub await ($to_wait) {
    waitpid($to_wait->{pid},0);
    confess("Timed out while waiting for event.") unless -f $to_wait->{file} && -s _;
    return Sereal::Decoder->decode_from_file($to_wait->{file});
}

1;
