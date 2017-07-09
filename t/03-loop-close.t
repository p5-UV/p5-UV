use strict;
use warnings;

use Test::More;
use UV;

use Data::Dumper;

my $loop_loc; # ${$loop}

{
    my $loop = UV::Loop->new();
    isa_ok($loop, 'UV::Loop', 'UV::Loop->new(): got a new Loop');
    $loop_loc = ${$loop};

    my $timer = UV::Timer->new($loop);
    isa_ok($timer, 'UV::Timer', 'timer: got a new timer');

    $timer->start(100, 100, sub {
        my $self = shift;
        isa_ok($self, 'UV::Timer', 'Got our timer in the callback');
        $self->loop()->stop();
    });

    is($loop->close(), UV::UV_EBUSY, 'loop->close: Returns EBUSY');

    $loop->run();

    $timer->close(sub {});

    is($loop->run(), 0, 'loop run: got zero');
}
done_testing();
