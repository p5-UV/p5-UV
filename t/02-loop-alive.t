use strict;
use warnings;

use Test::More;
use UV;

my $time = UV::hrtime();

sub timer_callback {
    my $self = shift;
    ok($self, 'Got a timer in the timer callback');
}

sub work_callback {
    my $self = shift;
    ok($self, 'Got a request in the work callback');
}
sub after_work_cb {
    my ($self, $status) = @_;
    ok($self, 'Got a request in the after_work callback');
    is($status, 0, 'Status is 0 in the after_work callback');
}

subtest 'loop_alive' => sub {
    my $r = 0;
    is(UV::default_loop()->alive(), 0, 'default loop is not alive');

    # loops with handles are alive
    my $timer = UV::Timer->new();
    $timer->start(100, 0, \&timer_callback);

    ok(UV::default_loop()->alive(), 'default loop is now alive!');

    $r = UV::default_loop()->run(UV::Loop::UV_RUN_DEFAULT);
    is($r, 0, 'loop ran fine');
    is(UV::default_loop()->alive(), 0, 'default loop is not alive anymore');

    # loops with requests are alive
    # $r = UV::default_loop->queue_work(uv_queue_work(uv_default_loop(), &work_req, work_cb, after_work_cb);
    # ASSERT(r == 0);
    # ASSERT(uv_loop_alive(uv_default_loop()));

    # r = uv_run(uv_default_loop(), UV_RUN_DEFAULT);
    # ASSERT(r == 0);
    # ASSERT(!uv_loop_alive(uv_default_loop()));
};

done_testing();

