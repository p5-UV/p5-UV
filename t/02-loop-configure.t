use strict;
use warnings;

use Test::More;
use UV;

# Some options behave differently on Windows
sub WINLIKE () {
        return 1 if $^O eq 'MSWin32';
        return 1 if $^O eq 'cygwin';
        return 1 if $^O eq 'msys';
        return '';
}

sub timer_cb {
    my $timer = shift;
    $timer->close();
}

{
    my $loop = UV::Loop->new();
    isa_ok($loop, 'UV::Loop', 'got a new loop');

    if (WINLIKE) {
        is(UV::UV_ENOSYS, $loop->configure(UV::UV_LOOP_BLOCK_SIGNAL, 0), 'Block signal does not work on Windows');
    }
    else {
        is(0, $loop->configure(UV::UV_LOOP_BLOCK_SIGNAL, UV::SIGPROF), 'Configure worked properly');
    }

    my $timer = UV::Timer->new($loop);
    isa_ok($timer, 'UV::Timer', 'got a new timer for the loop');
    is(0, $timer->start(10, 0, \&timer_cb), 'Timer started');

    is(0, $loop->run(UV::Loop::UV_RUN_DEFAULT), 'Loop started');
    is(0, $loop->close(), 'Loop closed');
}

done_testing();
