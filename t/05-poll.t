use strict;
use warnings;

use Test::More;

use Errno qw(EAGAIN ECONNRESET EINTR EWOULDBLOCK EINPROGRESS);
use FindBin;
use IO::Handle ();
use IO::Socket::INET;
use POSIX ();
use Socket qw(pack_sockaddr_in inet_aton SOL_SOCKET SO_ERROR);
use Try::Tiny qw(try catch);
use UV ();
use UV::Poll qw(UV_READABLE UV_WRITABLE UV_DISCONNECT UV_PRIORITIZED);
use UV::Timer ();

use constant UNIDIRECTIONAL => 0;
use constant DUPLEX => 1;
use constant NUM_CLIENTS => 5;
use constant TRANSFER_BYTES => (1 << 16);

my $CRLF = "\015\012";
my $WSAEWOULDBLOCK = 0;
if (my $ewould = Errno->can("WSAEWOULDBLOCK")) {
    $WSAEWOULDBLOCK = $ewould->();
}

sub non_blocking {
    my $num = shift;
    if ($^O eq 'MSWin32' || $^O eq 'msys') {
        return 1 if $num == $WSAEWOULDBLOCK;
    }
    else {
        return 1 if grep {$num == $_} (EWOULDBLOCK, EAGAIN, EINPROGRESS);
    }
    return 0;
}

sub poll_cb {
    my ($handle, $status, $events) = @_;
    my $context = $handle->data();
    ok($context, "poll_cb: got a context");
    if ($context->{connecting}) {
        my $err = $context->{client_sock}->getsockopt(SOL_SOCKET, SO_ERROR);
        if (!$err) {
            $context->{connecting} = 0;
            is($handle->stop(), 0, 'poll_cb: connecting, stopped');
            is($handle->start(UV_READABLE), 0, 'poll_cb: connecting: start readable');
        }
        elsif (non_blocking($err)) {
            return;
        }
        else {
            $handle->close();
            $context->{client_sock}->close();
            $context->{server_sock}->close();
            fail("Error connecting socket: $err");
        }
        return;
    }
    if ($events & UV_READABLE) {
        is($handle->stop(), 0, 'poll_cb: reading, stopped');
        my $read = $context->{client_sock}->sysread(my $buffer, 1024, 0);
        ok($read, "poll_cb: reading, read OK");
        is($buffer, "PING$CRLF", "poll_cb: reading, got PING");
        is($handle->start(UV_WRITABLE), 0, 'poll_cb: reading, poll started in writable mode');
    }
    elsif ($events & UV_WRITABLE) {
        is($handle->stop(), 0, 'poll_cb: writing, stopped');
        my $buffer = "PONG$CRLF";
        my $write = $context->{server_sock}->syswrite($buffer, length($buffer), 0);
        if ($write < 0) {
            ok(non_blocking($!), 'poll_cb: writing, got eagain');
        }
        else {
            ok($write, 'poll_cb: writing, Wrote some bytes');
        }
    }
}


sub get_context {
    my $context = {
        connecting => 0,
        server_sock => undef,
        client_sock => undef,
    };

    $context->{server_sock} = IO::Socket::INET->new(
        Type=>SOCK_STREAM,
        LocalAddr => '0.0.0.0',
        # ReusePort => 1,
        Blocking => 0,
        #Proto => Socket::IPPROTO_IP,
        Listen => 100,
    );
    ok(defined($context->{server_sock}), 'server_sock: IO::Socket::INET defined');
    ok( !$@, 'server_sock: got a good socket');

    $context->{client_sock} = IO::Socket::INET->new(
        Type=>SOCK_STREAM,
        PeerAddr => '127.0.0.1',
        PeerPort => $context->{server_sock}->sockport,
        # ReusePort => 1,
        Blocking => 0,
        #Proto => Socket::IPPROTO_IP,
    );
    ok(defined($context->{client_sock}), 'client_sock: IO::Socket::INET defined');
    ok( !$@, 'client_sock: got a good socket');
    return $context;
}

sub on_connection {
    my ($self, $server, $error) = @_;
    is($error, undef, "on_connection: no errors");
    # client = pyuv.TCP(self.loop)
    # server.accept(client)
    # self.client_connection = client
    # client.start_read(self.on_client_connection_read)
    # client.write(b"PING"+linesep)
}

#     def on_client_connection_read(self, client, data, error):
#         self.assertEqual(data, b"PONG"+linesep)
#         self.poll.close()
#         self.client_connection.close()
#         self.server.close()
#
# my $context = get_context();
# ok($context, 'got our context setup');
#
#
#     def test_poll(self):
#         self.server = pyuv.TCP(self.loop)
#         self.server.bind(("0.0.0.0", TEST_PORT))
#         self.server.listen(self.on_connection)
#         self.sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
#         self.sock.setblocking(False)
#         while True:
#             r = self.sock.connect_ex(("127.0.0.1", TEST_PORT))
#             if r and r != errno.EINTR:
#                 break
#         if r not in NONBLOCKING:
#             self.server.close()
#             self.fail("Error connecting socket: %d" % r)
#             return
#         self.connecting = True
#         self.poll = pyuv.Poll(self.loop, self.sock.fileno())
#         self.assertEqual(self.sock.fileno(), self.poll.fileno())
#         self.poll.start(pyuv.UV_WRITABLE, self.poll_cb)
#         self.loop.run()
#         self.assertTrue(self.poll.closed)
#         self.assertRaises(pyuv.error.HandleClosedError, self.poll.fileno)
#         self.sock.close()

ok(1);
done_testing();
