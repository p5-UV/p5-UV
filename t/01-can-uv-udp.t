use strict;
use warnings;

use UV::UDP ();

use Test::More;

# are all of the UV::Handle functions exportable as we expect?
can_ok('UV::UDP', (
    qw(new on close closed loop data),
    qw(active closing),
));

# are the extra methods also available?
can_ok('UV::UDP', (
    qw(open bind connect getpeername getsockname recv_start recv_stop),
    qw(send try_send),
));

done_testing;
