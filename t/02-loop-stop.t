use strict;
use warnings;

use Test::More;
use UV;

my $prepare_called = 0;
my $timer_called = 0;
my $num_ticks = 10;

my $timer;
my $prepare;

sub prepare_cb {
    my $handle = shift;
    is($handle, $prepare, 'Got the right prepare in the callback');
    $prepare_called++;
    $handle->stop() if ($prepare_called == $num_ticks);
}

sub timer_cb {
    my $handle = shift;
    is($handle, $timer, 'Got the right timer in the callback');
    $timer_called++;
    UV::default_loop()->stop() if ($timer_called == 1);
    $handle->stop() if ($timer_called == $num_ticks);
}

{
    my $r;
    $timer = UV::Timer->new();
    $prepare = UV::Prepare->new();

    $prepare->start(\&prepare_cb);
    $timer->start(100, 100, \&timer_cb);

    $r = UV::default_loop()->run(UV::Loop::UV_RUN_DEFAULT);
    ok($r != 0, 'Loop ran fine!');
    is($timer_called, 1, "Timer has been called once");

    $r = UV::default_loop()->run(UV::Loop::UV_RUN_NOWAIT);
    ok($r != 0, 'Loop ran fine!');
    ok($prepare_called > 1, 'Prepare has been called more than once');

    $r = UV::default_loop()->run(UV::Loop::UV_RUN_DEFAULT);
    is($r, 0, 'Loop ran fine!');

    is($timer_called, 10, 'Timer has been called 10 times');
    is($prepare_called, 10, 'Prepare has been called 10 times');
}

done_testing();
