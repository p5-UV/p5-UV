use strict;
use warnings;

use UV::Loop ();
use UV::UDP ();

use Test::More;

use IO::Socket::INET;
use Socket;

sub sockaddr_port { (Socket::unpack_sockaddr_in $_[0])[0] }

my $udp = UV::UDP->new;
isa_ok($udp, 'UV::UDP');

$udp->bind(Socket::pack_sockaddr_in(0, Socket::INADDR_LOOPBACK));

my $port = sockaddr_port($udp->getsockname);

# send + addr
{
    my $udp2 = UV::UDP->new;

    $udp2->send("data by address", Socket::pack_sockaddr_in($port, Socket::INADDR_LOOPBACK));

    my $recv_cb_called;
    $udp->on(recv => sub {
        my ($self, $status, $buf, $addr) = @_;
        $recv_cb_called++;

        is($buf, "data by address",  'data was received from udp socket');

        $self->close;
    });
    my $ret = $udp->recv_start;
    is($ret, $udp, '$udp->read_start returns $udp');

    UV::Loop->default->run;
    ok($recv_cb_called, 'recv callback was called');
}

done_testing();
