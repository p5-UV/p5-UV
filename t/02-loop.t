use strict;
use warnings;

use Test::More;
use UV;

use Data::Dumper;

my $default_loc; # ${$loop}

# default loop
{
    my $loop = UV::Loop->new(1);
    isa_ok($loop, 'UV::Loop', '->new(1): got a new default loop');
    $default_loc = ${$loop};
    my $now = $loop->now();
    ok($now, '  ->now: got a response');
    is($loop->loop_alive, 0, '  ->loop_alive: should get 0');
    is($loop->alive, 0, '  ->alive: should get 0');
    is($loop->backend_timeout, 0, '  ->backend_timeout: should get 0');
    diag("Short sleep to test for new ->now");
    sleep(1);
    is($loop->run, 0, '  ->run(UV_RUN_DEFAULT)');
    $loop->update_time();
    ok($loop->now > $now, '  ->now: should be greater than initial after update_time');
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
    diag("Short sleep to test for new ->now");
    sleep(1);
    is($loop->run, 0, '  ->run(UV_RUN_DEFAULT)');
    $loop->update_time();
    ok($loop->now > $now, '  ->now: should be greater than initial after update_time');
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
    diag("Short sleep to test for new ->now");
    sleep(1);
    is($loop->run, 0, '  ->run(UV_RUN_DEFAULT)');
    $loop->update_time();
    ok($loop->now > $now, '  ->now: should be greater than initial after update_time');
    is($loop->alive, 0, '  ->alive: should get 0');
    is($loop->backend_timeout, 0, '  ->backend_timeout: should get 0');
    ok($loop->backend_fd, '  ->backend_fd: found the backend FD');
}

done_testing();
