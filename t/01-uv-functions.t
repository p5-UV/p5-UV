use strict;
use warnings;

use Test::More;
use UV ();

{
    my $time = UV::hrtime();
    ok($time, "hrtime: got back - $time");
    ok(UV::hrtime(), "hrtime - no assignment");
    diag("Using v".UV::version_string());
    ok(UV::version_string(), 'got a version string');
    ok(UV::version(), 'got a version hex');
    is(UV::strerror(UV::UV_ENOSYS), 'function not implemented', 'Got the right constant value');
    is(UV::err_name(UV::UV_ENOSYS), 'ENOSYS', 'Got the right constant name');
}

{
    my $loop = UV::loop();
    isa_ok($loop, 'UV::Loop', 'got back the loop');
    is($loop->is_default(), 1, 'is the default loop');
    my $loop2 = UV::loop();
    isa_ok($loop2, 'UV::Loop', 'got back the loop');
    is($loop2->is_default(), 1, 'is the default loop');
    is($loop, $loop2, 'They are the same loop');
}

{
    my $handle = UV::check();
    isa_ok($handle, 'UV::Check', 'got back a Check handle');
    isa_ok($handle, 'UV::Handle', 'it derrives from UV::Handle');
    is($handle->loop()->is_default(), 1, 'Handle uses the default loop');
}

{
    my $handle = UV::idle();
    isa_ok($handle, 'UV::Idle', 'got back an Idle handle');
    isa_ok($handle, 'UV::Handle', 'it derrives from UV::Handle');
    is($handle->loop()->is_default(), 1, 'Handle uses the default loop')
}

{
    my $handle = UV::poll(fd => fileno(\*STDIN));
    isa_ok($handle, 'UV::Poll', 'got back an Poll handle');
    isa_ok($handle, 'UV::Handle', 'it derrives from UV::Handle');
    is($handle->loop()->is_default(), 1, 'Handle uses the default loop')
}

{
    my $handle = UV::prepare();
    isa_ok($handle, 'UV::Prepare', 'got back an Prepare handle');
    isa_ok($handle, 'UV::Handle', 'it derrives from UV::Handle');
    is($handle->loop()->is_default(), 1, 'Handle uses the default loop')
}

{
    my $handle = UV::timer();
    isa_ok($handle, 'UV::Timer', 'got back an Timer handle');
    isa_ok($handle, 'UV::Handle', 'it derrives from UV::Handle');
    is($handle->loop()->is_default(), 1, 'Handle uses the default loop')
}

done_testing();
