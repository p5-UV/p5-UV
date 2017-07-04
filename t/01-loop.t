use strict;
use warnings;
use Data::Dumper;

use Test::More;

use UV;


{
    my $time = UV::hrtime();
    ok($time, "hrtime: got back - $time");
}

my $loop = UV::Loop->new(1);
warn Dumper $loop;
{
    my $time = UV::hrtime();
    ok($time, "hrtime: got back - $time");
}
my $loop2 = UV::Loop->default_loop();
{
    my $time = UV::hrtime();
    ok($time, "hrtime: got back - $time");
}
warn Dumper $loop2;
isa_ok($loop, 'UV::Loop', "loop: got a default loop");

done_testing();
