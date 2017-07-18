use strict;
use warnings;

use Test::More;
use UV;

sub _cleanup_loop {
    my $loop = shift;
    $loop->walk(sub {shift->close()});
    $loop->run(UV::Loop::UV_RUN_DEFAULT);
    $loop->close();
}

my $close_cb_called = 0;
my $repeat_1_cb_called = 0;
my $repeat_2_cb_called = 0;
my $repeat_2_cb_allowed = 0;

my $dummy;      # timer
my $repeat_1;   # timer
my $repeat_2;   # timer

my $start_time;

sub close_cb {
    my $handle = shift;
    ok($handle, 'Got a handle in the close callback');
    $close_cb_called++;
}

sub repeat_1_cb {
    my $handle = shift;
    is($handle, $repeat_1, 'Got the right handle in the repeat_1 cb');

    my $ms = UV::default_loop()->now() - $start_time;
    diag("repeat_1_cb called after $ms ms");

    is($handle->get_repeat(), 50, 'Got the right timer repeat value');
    $repeat_1_cb_called++;

    is(0, $repeat_2->again(), 'Repeat 2 again success');
    if ($repeat_1_cb_called == 10) {
        $handle->close(\&close_cb);
        # we're not calling ->again on repeat_2 anymore. so after this,
        # timer_2_cb is expected
        $repeat_2_cb_allowed = 1;
    }
}

sub repeat_2_cb {
    my $handle = shift;
    is($handle, $repeat_2, 'Got the right handle in repeat 2 cb');
    ok($repeat_2_cb_allowed, 'repeat 2 cb allowed');

    my $ms = UV::default_loop()->now() - $start_time;
    diag("repeat_2_cb called after $ms ms");
    $repeat_2_cb_called++;

    if (0 == $repeat_2->get_repeat()) {
        is(0, $handle->is_active(), 'not active');
        $handle->close(\&close_cb);
        return;
    }
    is(100, $repeat_2->get_repeat(), 'Repeat 2 repeat correct');
    $repeat_2->set_repeat(0);
}

{
    $start_time = UV::default_loop()->now();
    ok(0 < $start_time, "got a positive start time");

    # Verify that it is not possible to uv_timer_again a never-started timer
    $dummy = UV::Timer->new();
    isa_ok($dummy, 'UV::Timer', 'Got a new timer');
    is(UV::UV_EINVAL, $dummy->again(), '->again erred as expected');
    $dummy->unref();

    # Start timer repeat_1
    $repeat_1 = UV::Timer->new();
    isa_ok($repeat_1, 'UV::Timer', 'repeat_1 timer new');
    is(0, $repeat_1->start(50, 0, \&repeat_1_cb), 'repeat_1 started');
    is(0, $repeat_1->get_repeat(), 'repeat_1 has the right repeat');

    # Actually make repeat_1 repeating
    $repeat_1->set_repeat(50);
    is(50, $repeat_1->get_repeat(), 'got the right repeat value');

    # Start another repeating timer. It'll be again()ed by the repeat_1 so
    # it should not time out until repeat_1 stops
    $repeat_2 = UV::Timer->new();
    isa_ok($repeat_2, 'UV::Timer', 'repeat_2 timer new');
    is(0, $repeat_2->start(100, 100, \&repeat_2_cb), 'repeat_2 started');
    is(100, $repeat_2->get_repeat(), 'Got the right repeat value for repeat_2');

    UV::default_loop()->run(UV::Loop::UV_RUN_DEFAULT);

    is(10, $repeat_1_cb_called, 'repeat 1 called 10 times');
    is(2, $repeat_2_cb_called, 'repeat 2 called 2 times');
    is(2, $close_cb_called, 'close cb called 2 times');

    my $ms = UV::default_loop()->now() - $start_time;
    diag("Test took $ms ms (expected ~700ms)");
    _cleanup_loop(UV::default_loop());
}

done_testing();
