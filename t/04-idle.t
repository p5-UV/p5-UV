use strict;
use warnings;

use Test::More;
use UV;

my $idle_handle;
my $check_handle;
my $timer_handle;

my $idle_cb_called = 0;
my $check_cb_called = 0;
my $timer_cb_called = 0;
my $close_cb_called = 0;


sub close_cb {
    $close_cb_called++;
}


sub timer_cb {
    my $handle = shift;
    is($handle, $timer_handle, 'got the proper timer handle');

    $idle_handle->close(\&close_cb);
    $check_handle->close(\&close_cb);
    $timer_handle->close(\&close_cb);

    $timer_cb_called++;
}


sub idle_cb {
    my $handle = shift;
    is($handle, $idle_handle, 'got the proper idle handle');

    $idle_cb_called++;
}


sub check_cb {
    my $handle = shift;
    is($handle, $check_handle, 'got the proper check handle');

    $check_cb_called++;
}

{
    $idle_handle = UV::Idle->new();
    isa_ok($idle_handle, 'UV::Idle', 'got a new idle handle');
    is($idle_handle->start(\&idle_cb), 0, 'Idle handle started');

    $check_handle = UV::Check->new();
    isa_ok($check_handle, 'UV::Check', 'got a new check handle');
    is($check_handle->start(\&check_cb), 0, 'Check handle started');

    $timer_handle = UV::Timer->new();
    isa_ok($timer_handle, 'UV::Timer', 'got a new timer handle');
    is($timer_handle->start(50, 0, \&timer_cb), 0, 'Timer handle started');

    is(UV::default_loop()->run(), 0, 'default_loop run');

    ok($idle_cb_called > 0, 'idle cb called');
    is($timer_cb_called, 1, 'timer cb called once');
    is($close_cb_called, 3, 'close cb called 3 times');
}

done_testing();
