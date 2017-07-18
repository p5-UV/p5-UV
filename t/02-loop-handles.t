use strict;
use warnings;

use Test::More;
use UV;

use constant IDLE_COUNT => 7;
use constant ITERATIONS => 21;
use constant TIMEOUT => 100;

sub _cleanup_loop {
    my $loop = shift;
    $loop->walk(sub {shift->close()});
    $loop->run(UV::Loop::UV_RUN_DEFAULT);
    $loop->close();
}

# prepare handles
my $prepare_1_handle;
my $prepare_2_handle;

# check handle
my $check_handle;

# idle handles
my @idle_1_handles;
my $idle_2;

# timer handles
my $timer_handle;

# counts
my $loop_iteration = 0;
my $prepare_1_cb_called = 0;
my $prepare_1_close_cb_called = 0;
my $prepare_2_cb_called = 0;
my $prepare_2_close_cb_called = 0;
my $check_cb_called = 0;
my $check_close_cb_called = 0;
my $idle_1_cb_called = 0;
my $idle_1_close_cb_called = 0;
my $idles_1_active = 0;
my $idle_2_cb_called = 0;
my $idle_2_close_cb_called = 0;
my $idle_2_cb_started = 0;
my $idle_2_is_active = 0;


sub timer_cb {
    my $handle = shift;
    is($handle, $timer_handle, 'Got the timer handle');
}

sub idle_2_close_cb {
    my $handle = shift;
    is($handle, $idle_2, 'Got the right idle_2 handle');
    ok($idle_2_is_active, 'Idle2 is active');
    $idle_2_close_cb_called++;
    $idle_2_is_active = 0;
}

sub idle_2_cb {
    my $handle = shift;
    is($handle, $idle_2, 'Got the right idle_2 handle');

    $idle_2_cb_called++;
    $handle->close(\&idle_2_close_cb);
}


sub idle_1_cb {
    my $handle = shift;

    ok($handle, 'Got an idle_1 handle');
    ok($idles_1_active > 0, 'Idles_1 active');

    # Init idle_2 and make it active
    if (!$idle_2_is_active && (!$idle_2 || ($idle_2 && !$idle_2->closing()))) {
        $idle_2 = UV::Idle->new();
        isa_ok($idle_2, 'UV::Idle', 'idle_2_handle created');
        is($idle_2->start(\&idle_2_cb), 0, 'Idle_2 started');
        $idle_2_is_active = 1;
        $idle_2_cb_started++;
    }

    $idle_1_cb_called++;

    if ($idle_1_cb_called % 5 == 0) {
        is($handle->stop(), 0, "idle 1 handle stopped");
        $idles_1_active--;
    }
}

sub idle_1_close_cb {
    my $handle = shift;
    ok($handle, 'Got an idle 1 handle');
    $idle_1_close_cb_called++;
}


sub prepare_1_close_cb {
    my $handle = shift;
    is($handle, $prepare_1_handle, 'Got the prepare_1_handle');
    $prepare_1_close_cb_called++;
}


sub check_close_cb {
    my $handle = shift;
    is($handle, $check_handle, 'Got the check handle');
    $check_close_cb_called++;
}


sub prepare_2_close_cb {
    my $handle = shift;
    is($handle, $prepare_2_handle, 'got the prepare_2 handle');
    $prepare_2_close_cb_called++;
}


sub check_cb {
    my $handle = shift;
    is($handle, $check_handle, 'Got the check handle');

    if ($loop_iteration < ITERATIONS) {
        # Make some idle watchers active
        for my $i (0 .. ($loop_iteration % IDLE_COUNT)) {
            is($idle_1_handles[$i]->start(\&idle_1_cb), 0, 'idle 1 handle started');
            $idles_1_active++;
        }
    }
    else {
        # End of the test - close all handles
        $prepare_1_handle->close(\&prepare_1_close_cb);
        $check_handle->close(\&check_close_cb);
        $prepare_2_handle->close(\&prepare_2_close_cb);

        for my $idle (@idle_1_handles) {
            $idle->close(\&idle_1_close_cb);
        }

        # This handle is closed/recreated every time, close it only if it is
        # active
        if ($idle_2_is_active) {
            $idle_2->close(\&idle_2_close_cb);
        }
    }
    $check_cb_called++;
}


sub prepare_2_cb {
    my $handle = shift;
    is($handle, $prepare_2_handle, 'Got the right prepare 2 handle');

    # prepare_2 gets started by prepare_1 when (loop_iteration % 2 == 0),
    # and it stops itself immediately. A started watcher is not queued
    # until the next round, so when this callback is made
    # (loop_iteration % 2 == 0) cannot be true.
    ok($loop_iteration % 2 != 0, 'not on an even loop iteration');

    is($handle->stop(), 0, 'prepare handle stopped');
    $prepare_2_cb_called++;
}


sub prepare_1_cb {
    my $handle = shift;
    is($handle, $prepare_1_handle, 'Got the right prepare 1 handle');

    if ($loop_iteration % 2 == 0) {
        is($prepare_2_handle->start(\&prepare_2_cb), 0, 'prepare_2 started');
    }

    $prepare_1_cb_called++;
    $loop_iteration++;
    diag("Loop iteration $loop_iteration of ". ITERATIONS);
}


{
    $prepare_1_handle = UV::Prepare->new();
    isa_ok($prepare_1_handle, 'UV::Prepare', 'prepare 1 handle good');
    is(0, $prepare_1_handle->start(\&prepare_1_cb), 'prepare 1 handle started');

    $check_handle = UV::Check->new();
    isa_ok($check_handle, 'UV::Check', 'Got a new check handle');
    is(0, $check_handle->start(\&check_cb), 'check started');

    # initialize only, prepare_2 is started by prepare_1_cb
    $prepare_2_handle = UV::Prepare->new();
    isa_ok($prepare_2_handle, 'UV::Prepare', 'Got a new prepare 2 handle');

    for my $i (0 .. IDLE_COUNT-1) {
        # initialize only, idle_1 handles are started by check_cb
        my $handle = UV::Idle->new();
        isa_ok($handle, 'UV::Idle', "New Idle handle setup");
        push @idle_1_handles, $handle;
    }

    # don't init or start idle_2, both is done by idle_1_cb
    #
    # the timer callback is there to keep the event loop polling
    # unref it as it is not supposed to keep the loop alive
    $timer_handle = UV::Timer->new();
    isa_ok($timer_handle, 'UV::Timer', 'Got a new timer');
    is(0, $timer_handle->start(TIMEOUT, TIMEOUT, \&timer_cb), "Timer started");
    # TODO
    $timer_handle->unref();

    is(0, UV::default_loop()->run(UV::Loop::UV_RUN_DEFAULT), 'default loop ran');

    is($loop_iteration, ITERATIONS, 'Right number of loop iterations');

    is($prepare_1_cb_called, ITERATIONS, 'Right num of prepare 1 cbs');
    is($prepare_1_close_cb_called, 1, 'Right num of prepare 1 close cbs');

    is($prepare_2_cb_called, int(ITERATIONS / 2.0), 'Right num of prep 2 cbs');
    is($prepare_2_close_cb_called, 1, 'Right num of prep 2 close cbs');

    is($check_cb_called, ITERATIONS, 'Right num check cbs');
    is($check_close_cb_called, 1, 'Right num check close cbs');

    # idle_1_cb should be called a lot
    is($idle_1_close_cb_called, IDLE_COUNT, 'Right num idle 1 close cbs');

    is($idle_2_close_cb_called, $idle_2_cb_started, 'Idle 2 closes = idle 2 starts');
    is($idle_2_is_active, 0, 'no idle 2 active');
    _cleanup_loop(UV::default_loop());
}

done_testing();
