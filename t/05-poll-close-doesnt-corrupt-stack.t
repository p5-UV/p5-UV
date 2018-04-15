use strict;
use warnings;

use Test::More;
use IO::Socket::INET;
use UV ();
use UV::Loop ();
use UV::Poll qw(UV_READABLE UV_WRITABLE);
plan skip_all => 'Test is currently broken';

# Some options behave differently on Windows
sub WINLIKE () {
    return 1 if $^O eq 'MSWin32';
    return 1 if $^O eq 'cygwin';
    return 1 if $^O eq 'msys';
    return '';
}
plan skip_all => 'Windows only testing' unless WINLIKE();

my $sock;
my $handle;

my $close_cb_called = 0;


sub close_cb {
    $close_cb_called++;
}

sub poll_cb {
    fail("Should never have gotten to the poll_cb");
    exit(1);
}

sub close_socket_and_verify_stack {
    my $MARKER = 0xDEADBEEF;
    my $VERIFY_AFTER = 0.001 * 10; # ms
    my $r;

    my @data;

    for my $i (0 .. 65535) {
        $data[$i] = $MARKER;
    }
    $sock->close();
    # sleep for X milliseconds
    select(undef, undef, undef, $VERIFY_AFTER);

    for my $i (0 .. 65535) {
        ok($data[$i] == $MARKER);
    }
}

{
    $sock = IO::Socket::INET->new(Type => SOCK_STREAM);

    $handle = UV::Poll->new(on_poll => \&poll_cb, on_close => \&close_cb, fd=>fileno($sock));
    is($handle->start(UV_READABLE | UV_WRITABLE), 0, 'poll started');
    $handle->close();

    close_socket_and_verify_stack();

    is(UV::Loop->default()->run(), 0, 'default loop ran');
    is($close_cb_called, 1, 'right number of close CBs called');
}

done_testing();
