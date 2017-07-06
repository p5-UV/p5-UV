use strict;
use warnings;

use Test::More;
use UV;

use Data::Dumper;

my $default_loc; # ${$loop}

# default loop run for 1 second
{
    my $loop = UV::Loop->default_loop();
    isa_ok($loop, 'UV::Loop', 'default_loop(): got a new loop');
    $default_loc = ${$loop};
    my $start = $loop->now();
    ok($start, "  Start time is $start");
    while ($loop->now() - $start < 500) {
        is(0, $loop->run(UV::Loop::UV_RUN_NOWAIT), "  run(UV_RUN_NOWAIT): ok for a half-second");
    }
}

# non-default loop run for 1 second
{
    my $loop = UV::Loop->new();
    isa_ok($loop, 'UV::Loop', 'new(): got a non-default new loop');
    my $start = $loop->now();
    ok($start, "  Start time is $start");
    while ($loop->now() - $start < 500) {
        is(0, $loop->run(UV::Loop::UV_RUN_NOWAIT), "  run(UV_RUN_NOWAIT): ok for a half-second");
    }
}

# default loop
{
    my $loop = UV::Loop->new(1);
    isa_ok($loop, 'UV::Loop', '->new(1): got a new default loop');
    my $now = $loop->now();
    ok($now, '  ->now: got a response');
    is($loop->loop_alive, 0, '  ->loop_alive: should get 0');
    is($loop->alive, 0, '  ->alive: should get 0');
    is($loop->backend_timeout, 0, '  ->backend_timeout: should get 0');
    is($loop->run, 0, '  ->run(UV_RUN_DEFAULT)');
    $loop->update_time();
    is($loop->alive, 0, '  ->alive: should get 0');
    is($loop->backend_timeout, 0, '  ->backend_timeout: should get 0');
    ok($loop->backend_fd, '  ->backend_fd: found the backend FD');
}

# another copy of the default loop
{
    my $loop = UV::Loop->default_loop();
    isa_ok($loop, 'UV::Loop', '->default_loop: got a new default loop');
    is($default_loc, ${$loop}, '  Previous default loop and this one are one in the same');
    my $now = $loop->now();
    ok($now, '  ->now: got a response');
    is($loop->alive, 0, '  ->alive: should get 0');
    is($loop->backend_timeout, 0, '  ->backend_timeout: should get 0');
    is($loop->run, 0, '  ->run(UV_RUN_DEFAULT)');
    $loop->update_time();
    is($loop->alive, 0, '  ->alive: should get 0');
    is($loop->backend_timeout, 0, '  ->backend_timeout: should get 0');
    ok($loop->backend_fd, '  ->backend_fd: found the backend FD');
}

# a non-default loop
{
    my $loop = UV::Loop->new();
    isa_ok($loop, 'UV::Loop', '->new: got a new non-default loop');
    ok($default_loc != ${$loop}, '  Non-default loop is not same as default');
    my $now = $loop->now();
    ok($now, '  ->now: got a response');
    is($loop->alive, 0, '  ->alive: should get 0');
    is($loop->backend_timeout, 0, '  ->backend_timeout: should get 0');
    is($loop->run, 0, '  ->run(UV_RUN_DEFAULT)');
    $loop->update_time();
    is($loop->alive, 0, '  ->alive: should get 0');
    is($loop->backend_timeout, 0, '  ->backend_timeout: should get 0');
    ok($loop->backend_fd, '  ->backend_fd: found the backend FD');
}

done_testing();
