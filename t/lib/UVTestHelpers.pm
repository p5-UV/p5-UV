package UVTestHelpers;

use strict;
use warnings;

use Exporter 'import';
our @EXPORT_OK = qw(
    pipepair
);

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

1;
