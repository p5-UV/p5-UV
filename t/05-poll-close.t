use strict;
use warnings;

use Test::More;
use IO::Socket::INET;
use UV;
use UV::Loop ();
use UV::Poll qw(UV_READABLE UV_WRITABLE);

# Some options behave differently on Windows
sub WINLIKE () {
    return 1 if $^O eq 'MSWin32';
    return 1 if $^O eq 'cygwin';
    return 1 if $^O eq 'msys';
    return '';
}

sub _cleanup_loop {
    my $loop = shift;
    $loop->walk(sub {
        my $handle = shift;
        $handle->stop() if $handle->can('stop');
        $handle->close() unless $handle->closing();
    });
    $loop->run(UV::Loop::UV_RUN_DEFAULT);
    is($loop->close(), 0, 'loop closed');
}

my $NUM_SOCKETS = 64;


my $close_cb_called = 0;


sub close_cb {
    $close_cb_called++;
}

subtest 'poll_close' => sub {
    my @sockets;
    my @handles;

    for my $i (0 .. $NUM_SOCKETS-1) {
        my $socket = IO::Socket::INET->new(Type => SOCK_STREAM);
        my $handle = UV::Poll->new($socket);
        push @sockets, $socket;
        push @handles, $handle;
        $handle->start(UV_READABLE | UV_WRITABLE, undef);
    }

    for my $handle (@handles) {
        $handle->close(\&close_cb);
    }

    is(UV::Loop->default_loop()->run(), 0, 'default loop run');
    is($close_cb_called, $NUM_SOCKETS, 'Got the right number of close CBs');

    _cleanup_loop(UV::Loop->default_loop());
};

done_testing();
