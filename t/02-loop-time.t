use strict;
use warnings;

use UV::Loop qw(UV_RUN_NOWAIT);
use UV::Timer ();
use Test::More;

sub _cleanup_loop {
    my $loop = shift;
    $loop->walk(sub {diag(" -> walking");shift->close()});
    $loop->run(UV::Loop::UV_RUN_DEFAULT);
    is($loop->close(), 0, 'loop closed');;
}

{
    my $start = UV::Loop->default()->now();
    ok($start, "  Start time is $start");
    while (UV::Loop->default->now() - $start < 500) {
        is(0, UV::Loop->default()->run(UV_RUN_NOWAIT), "  run(UV_RUN_NOWAIT): ok for a half-second");
    }
    _cleanup_loop(UV::Loop->default());
}

{
    my $loop = UV::Loop->new();
    isa_ok($loop, 'UV::Loop', 'got a new loop');
    my $start = $loop->now();
    ok($start, "  Start time is $start");
    while ($loop->now() - $start < 500) {
        is(0, $loop->run(UV_RUN_NOWAIT), "  run(UV_RUN_NOWAIT): ok for a half-second");
    }
    _cleanup_loop($loop);
}

sub cb {
    my $timer = shift;
    $timer->close(undef);
}

{
    my $loop = UV::Loop->default();
    isa_ok($loop, 'UV::Loop', '->default(): got a new default Loop');
    my $timer = UV::Timer->new();
    isa_ok($timer, 'UV::Timer', 'timer: got a new timer');

    is($loop->alive(), 0, 'loop->alive: not alive yet');
    is($loop->backend_timeout(), 0, 'loop->backend_timeout: still zero');

    is($timer->start(1000, 0, \&cb), 0, 'timer: started correctly');

    ok($loop->backend_timeout() > 100, 'backend_timeout > 0.1 sec' );
    ok($loop->backend_timeout() <= 1000, 'backend_timeout <= 1 sec');

    is($loop->run(), 0, 'run: ran successfully');

    is($loop->backend_timeout(), 0, "backend_timeout now 0 secs");
    _cleanup_loop($loop);
}

done_testing();
