use strict;
use warnings;

use Test::More;
use UV;


sub timer_callback {
    my $self = shift;
    ok($self, 'Got a timer in the timer callback');
}

is(UV::default_loop()->alive(), 0, 'default loop is not alive');

# loops with handles are alive
my $timer = UV::Timer->new();
$timer->start(100, 0, \&timer_callback);

ok(UV::default_loop()->alive(), 'default loop is now alive!');

my $r = UV::default_loop()->run(UV::Loop::UV_RUN_DEFAULT);
is($r, 0, 'loop ran fine');

UV::default_loop()->close();

is(UV::default_loop()->alive(), 0, 'default loop is not alive anymore');
done_testing();
