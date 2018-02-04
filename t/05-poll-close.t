use strict;
use warnings;

use Test::More;
use IO::Socket::INET;
use UV ();
use UV::Loop ();
use UV::Poll qw(UV_READABLE UV_WRITABLE);

my $NUM_SOCKETS = 64;


my $close_cb_called = 0;


sub close_cb {
    $close_cb_called++;
}

{
    my @sockets;
    my @handles;

    for my $i (0 .. $NUM_SOCKETS-1) {
        my $socket = IO::Socket::INET->new(Type => SOCK_STREAM);
        my $handle = UV::Poll->new(socket => 1, fd => fileno($socket));
        push @sockets, $socket;
        push @handles, $handle;
        $handle->start(UV_READABLE | UV_WRITABLE, undef);
    }

    for my $handle (@handles) {
        $handle->close(\&close_cb);
    }

    is(UV::Loop->default()->run(), 0, 'default loop run');
    is($close_cb_called, $NUM_SOCKETS, 'Got the right number of close CBs');

}

done_testing();
