use strict;
use warnings;

use Test::More;
use UV::Loop qw(UV_RUN_DEFAULT);

{
    my $l = UV::Loop->default(); # singleton
    is($l->alive(), 0, 'Default loop is not alive');
    my $l2 = UV::Loop->default(); # singleton
    is($l, $l2, 'Got the same default loop');
}

{
    my $loop = UV::Loop->default_loop();
    is($loop->alive(), 0, 'default loop is not alive');
    $loop->run(UV_RUN_DEFAULT);
}

{
    my $loop = UV::Loop->new(); # not a singleton
    is($loop->alive(), 0, 'Non-default loop is not alive');
}
my $loop = UV::Loop->default();
#{
    use UV::Timer ();
    my $timer = UV::Timer->new(
        loop => $loop,
        on_close => sub {print "Closing Timer\n"},
        on_timer => sub {print "Timing Timer\n"},
    );
    isa_ok($timer, 'UV::Timer', 'got a timer');
    is($timer->start(0,0), 0, 'timer started');
    is($loop->run(), 0, 'ran');
#}

# use Data::Dumper::Concise;
# print Dumper $timer;
# print "whaaaaat?\n";
$loop->close();
done_testing();
