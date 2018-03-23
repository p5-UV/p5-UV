use strict;
use warnings;

use Test::More;
use UV ();
use UV::Timer ();

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

{
    diag("Loop alive");
    my $r = 0;
    is(UV::default_loop()->alive(), 0, 'default loop is not alive');

    # loops with handles are alive
    my $timer = UV::Timer->new();
    $timer->start(100, 0, \&timer_callback);

    ok(UV::default_loop()->alive(), 'default loop is now alive!');

    $r = UV::default_loop()->run(UV::Loop::UV_RUN_DEFAULT);
    is($r, 0, 'loop ran fine');
    is(UV::default_loop()->alive(), 0, 'default loop is not alive anymore');
}

diag("the rest of these tests can't run until we implement uv_req_t objects");

# subtest 'work_loop_alive' => sub {
#     my $r = 0;
#     # loops with requests are alive
#     my $work = UV::Work->new();
#     isa_ok($work, 'UV::Work', 'got a new UV::Work request');
#
#     $r = $work->queue_work(UV::default_loop(), \&work_callback, \&after_work_cb);
#     is($r, 0, 'work queued successfully');
#     ok(UV::default_loop()->alive(), 'default loop has work and should be alive');
#
#     $r = UV::default_loop()->run(UV::Loop::UV_RUN_DEFAULT);
#     is($r, 0, 'loop ran fine');
#     is(UV::default_loop()->alive(), 0, 'default loop is not alive anymore');
# };

done_testing();
