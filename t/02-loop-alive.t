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

done_testing();
