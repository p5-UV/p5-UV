package UVTestHelpers;

use strict;
use warnings;

use Exporter 'import';
our @EXPORT_OK = qw(
    pipepair
    socketpair_inet_stream
    socketpair_inet_dgram
);

use IO::Socket::INET;
use Socket qw( AF_INET SOCK_STREAM INADDR_LOOPBACK pack_sockaddr_in );

sub pipepair_base
{
    pipe ( my( $rd, $wr ) ) or return;
    return ( $rd, $wr );
}

require IO::Socket::IP if $^O eq "MSWin32";

sub pipepair_MSWin32
{
    # MSWin32's pipes are insufficient for what we need.
    # MSWin32 also lacks a socketpair(), so we'll have to fake it up
    # Code inspired by IO::Async::OS::MSWin32

    my $family = AF_INET;
    my $socktype = SOCK_STREAM;

    my $Stmp = IO::Socket::IP->new->socket( $family, $socktype, 0 ) or return;
    $Stmp->bind( pack_sockaddr_in( 0, INADDR_LOOPBACK ) ) or return;

    my $S1 = IO::Socket::IP->new->socket( $family, $socktype, 0 ) or return;
    $Stmp->listen( 1 ) or return;
    $S1->connect( getsockname $Stmp ) or return;

    my $S2 = $Stmp->accept;

    return ( $S1, $S2 );
}

*pipepair = ( $^O eq "MSWin32" ) ? \&pipepair_MSWin32 : \&pipepair_base;

sub socketpair_inet_stream
{
    my ($rd, $wr);

    # Maybe socketpair(2) can do it?
    ($rd, $wr) = IO::Socket->socketpair(AF_INET, SOCK_STREAM, 0)
        and return ($rd, $wr);

    # If not, go the long way round
    my $listen = IO::Socket::INET->new(
        LocalHost => "127.0.0.1",
        LocalPort => 0,
        Listen    => 1,
    ) or die "Cannot listen - $@";

    $rd = IO::Socket::INET->new(
        PeerHost => $listen->sockhost,
        PeerPort => $listen->sockport,
    ) or die "Cannot connect - $@";

    $wr = $listen->accept or die "Cannot accept - $!";

    return ($rd, $wr);
}

sub socketpair_inet_dgram
{
    my ($rd, $wr);

    # Maybe socketpair(2) can do it?
    ($rd, $wr) = IO::Socket->socketpair(AF_INET, SOCK_DGRAM, 0)
        and return ($rd, $wr);

    # If not, go the long way round
    $rd = IO::Socket::INET->new(
        LocalHost => "127.0.0.1",
        LocalPort => 0,
        Proto     => "udp",
    ) or die "Cannot socket - $@";

    $wr = IO::Socket::INET->new(
        PeerHost => $rd->sockhost,
        PeerPort => $rd->sockport,
        Proto    => "udp",
    ) or die "Cannot socket/connect - $@";

    $rd->connect($wr->sockport, inet_aton($wr->sockhost)) or die "Cannot connect - $!";

    return ($rd, $wr);
}

1;
