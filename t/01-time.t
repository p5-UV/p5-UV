use strict;
use warnings;

use Test::More;
use UV;

my $time = UV::hrtime();
ok($time, "hrtime: got back - $time");

done_testing();
