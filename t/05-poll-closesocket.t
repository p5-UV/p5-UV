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

plan skip_all => 'Windows only tests' unless WINLIKE();

my $sock;
my $handle;
my $close_cb_called = 0;

sub close_cb {
    $close_cb_called++;
    $sock->close();
}

sub poll_cb {
    my ($h, $status, $events) = @_;
    is($status, 0, 'status is zero');
    is($h, $handle, 'got the right handle');

    is($handle->start(UV_READABLE), 0, 'poll started again in READABLE mode');

    $handle->close();
}

{
    $sock = IO::Socket::INET->new(Type => SOCK_STREAM);
    $handle = UV::Poll->new(on_poll => \&poll_cb, on_close => \&close_cb, fd => fileno($sock));
    isa_ok($handle, 'UV::Handle', 'Got a new POLL socket handle');

    is($handle->start(UV_WRITABLE), 0, 'poll started in WRITABLE mode');

    is(UV::Loop->default()->run(), 0, 'default loop run');
    is($close_cb_called, 1, 'Got the right number of close CBs');
}

done_testing();
