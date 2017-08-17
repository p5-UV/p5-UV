use strict;
use warnings;

use Test::More;

use Errno qw(EAGAIN ECONNRESET EINTR EWOULDBLOCK EINPROGRESS);
use FindBin;
use IO::Handle ();
use IO::Socket::INET;
use POSIX ();
use Socket qw(pack_sockaddr_in inet_aton);
use Try::Tiny qw(try catch);
use UV;
use UV::Poll qw(UV_READABLE UV_WRITABLE UV_DISCONNECT UV_PRIORITIZED);

use constant UNIDIRECTIONAL => 0;
use constant DUPLEX => 1;
use constant NUM_CLIENTS => 5;
use constant TRANSFER_BYTES => (1 << 16);

my $TEST_PORT;

my $test_mode = DUPLEX;
my $closed_connections = 0;
my $valid_writable_wakeups = 0;
my $spurious_writable_wakeups = 0;
my $disconnects = 0;

# Some options behave differently on Windows
sub WINLIKE () {
    return 1 if $^O eq 'MSWin32';
    return 1 if $^O eq 'cygwin';
    return 1 if $^O eq 'msys';
    return '';
}

sub MIN($$) {
    my ($x,$y) = @_;
    return $x if $x < $y;
    return $y;
}

sub _cleanup_loop {
    my $loop = shift;
    $loop->walk(sub {
        my $handle = shift;
        $handle->stop() if $handle->can('stop');
        $handle->close() unless $handle->closing();
    });
    $loop->run(UV::Loop::UV_RUN_DEFAULT);
    is($loop->close(), 0, 'loop closed');
}

sub _connection_context_new {
    return {
        poll_handle => undef,
        timer_handle => undef,
        sock => undef,
        read => 0,
        sent => 0,
        is_server_connection => 0,
        open_handles => 0,
        got_fin => 0,
        sent_fin => 0,
        got_disconnect => 0,
        events => 0,
        delayed_events => 0,
    };
}

sub _server_context_new {
    return {
        poll_handle => undef,
        sock => undef,
        connections => 0,
    };
}

sub got_eagain {
    my $error = shift;
    return 1 if $error == EWOULDBLOCK;
    return 1 if $error == EINPROGRESS;
    return 1 if $error == EAGAIN;
    return 0;
}

sub close_socket {
    my $sock = shift;
    $sock->close();
}


sub create_connection_context {
    my ($sock, $is_server_connection) = @_;
    my $context = _connection_context_new();

    $context->{sock} = $sock;
    $context->{is_server_connection} = $is_server_connection;

    $context->{poll_handle} = UV::Poll->new_socket(fileno($sock));
    isa_ok($context->{poll_handle}, 'UV::Poll', 'Got a new UV::Poll');

    $context->{open_handles}++;
    $context->{poll_handle}->data($context);

    $context->{timer_handle} = UV::Timer->new();
    isa_ok($context->{timer_handle}, 'UV::Timer', 'Got a new UV::Timer');

    $context->{open_handles}++;
    $context->{timer_handle}->data($context);
    return $context;
}


sub connection_close_cb {
    my $handle = shift;
    my $context = $handle->data;

    if (--$context->{open_handles} == 0) {
        if ($test_mode == DUPLEX || $context->{is_server_connection}) {
            is($context->{read}, TRANSFER_BYTES, 'DUPLEX: Server: right read');
        }
        else {
            is($context->{read}, 0, 'Read zero');
        }

        if ($test_mode == DUPLEX || !$context->{is_server_connection}) {
            is($context->{sent}, TRANSFER_BYTES, 'DUPLEX: client: right sent');
        }
        else {
            is($context->{sent}, 0, 'Sent zero');
        }
        $closed_connections++;
        $context = undef;
        $handle->data(undef);
    }
}


sub destroy_connection_context {
    my $context = shift;
    $context->{poll_handle}->close(\&connection_close_cb);
    $context->{timer_handle}->close(\&connection_close_cb);
}


sub connection_poll_cb {
    my ($handle, $status, $events) = @_;
    my $context = $handle->data;

    is($status, 0, 'Got the right status');
    ok($events & $context->{events}, 'Got the right context events');
    ok(!($events & ~$context->{events}), 'Got the right events');

    my $new_events = $context->{events};

    if ($events & UV_READABLE) {
        my $action = int(rand(7));
        # diag("read - $action");

        if ($action == 0 || $action == 1) {
            my $read = $context->{sock}->sysread(my $buffer, 74, 0);
            ok(defined $read && $read >= 0, 'read some bytes');
            if ($read) {
                $context->{read} += $read;
            }
            else {
                # Got FIN
                $context->{got_fin} = 1;
                $new_events &= ~UV_READABLE;
            }
        }
        elsif($action == 2 || $action == 3) {
            # Read until EAGAIN.
            my $read = $context->{sock}->sysread(my $buffer, 931, 0);
            ok(defined($read) && $read >= 0, 'read some bytes');

            while (defined($read) && $read > 0) {
                $context->{read} += $read;
                $read = $context->{sock}->sysread(my $buffer, 931, 0);
            }

            if (defined($read) && $read == 0) {
                # Got FIN.
                $context->{got_fin} = 1;
                $new_events &= ~UV_READABLE;
            }
            else {
                ok(got_eagain($!), 'got EAGAIN');
            }
        }
        elsif ($action == 4) {
            pass("got the ignore case");
        }
        elsif ($action == 5) {
            # Stop reading for a while. Restart in timer callback.
            $new_events &= ~UV_READABLE;
            if (!$context->{timer_handle}->active()) {
                $context->{delayed_events} = UV_READABLE;
                $context->{timer_handle}->start(10, 0, \&delay_timer_cb);
            }
            else {
                $context->{delayed_events} |= UV_READABLE;
            }
        }
        elsif ($action == 6) {
            # Fudge with the event mask.
            $context->{poll_handle}->start(UV_WRITABLE, \&connection_poll_cb);
            $context->{poll_handle}->start(UV_READABLE, \&connection_poll_cb);
            $context->{events} = UV_READABLE;
        }
        else {
            fail("We should never get here");
        }
    }

    if ($events & UV_WRITABLE) {
        if ($context->{sent} < TRANSFER_BYTES && !($test_mode == UNIDIRECTIONAL && $context->{is_server_connection})) {
            # We have to send more bytes.
            my $action = int(rand(7));
            # diag("write - $action");

            if ($action == 0 || $action == 1) {
                # Send a couple of bytes.
                my $buffer = 'f' x 103;
                my $send_bytes = MIN(TRANSFER_BYTES - $context->{sent}, length($buffer));
                ok($send_bytes, 'have some bytes to send');

                my $written = $context->{sock}->syswrite($buffer, $send_bytes, 0);
                if ($written < 0) {
                    ok(got_eagain($!), 'got eagain');
                    $spurious_writable_wakeups++;
                }
                else {
                    ok($written, 'wrote some bytes');
                    $context->{sent} += $written;
                    $valid_writable_wakeups++;
                }
            }
            elsif ($action == 2 || $action == 3) {
                # Send until EAGAIN.
                my $buffer = 'f' x 1234;
                my $send_bytes = MIN(TRANSFER_BYTES - $context->{sent}, length($buffer));
                ok($send_bytes, 'have some bytes to send');

                my $written = $context->{sock}->syswrite($buffer, $send_bytes, 0);

                if ($written < 0) {
                    ok(got_eagain($!), 'got EAGAIN');
                    $spurious_writable_wakeups++;
                }
                else {
                    ok($written, 'Wrote some bytes');
                    $valid_writable_wakeups++;
                    $context->{sent} += $written;

                    while ($context->{sent} < TRANSFER_BYTES) {
                        $send_bytes = MIN(TRANSFER_BYTES - $context->{sent}, length($buffer));
                        ok($send_bytes, 'have some bytes to send');
                        $written = $context->{sock}->syswrite($buffer, $send_bytes, 0);
                        last unless $written;
                        $context->{sent} += $written;
                    }
                    ok($written || got_eagain($!), 'wrote or got eagain');
                }
            }
            elsif ($action == 4) {
                pass("ignore this case");
            }
            elsif ($action == 5) {
                # Stop sending for a while. Restart in timer callback.
                $new_events &= ~UV_WRITABLE;
                if ($context->{timer_handle}->active()) {
                    $context->{delayed_events} |= UV_WRITABLE;
                }
                else {
                    $context->{delayed_events} = UV_WRITABLE;
                    $context->{timer_handle}->start(100, 0, \&delay_timer_cb);
                }
            }
            elsif ($action == 6) {
                # Fudge with the event mask.
                $context->{poll_handle}->start(UV_READABLE, \&connection_poll_cb);
                $context->{poll_handle}->start(UV_WRITABLE, \&connection_poll_cb);
                $context->{events} = UV_WRITABLE;
            }
            else {
                fail("Should have never gotten here");
            }
        }
        else {
            # Nothing more to write. Send FIN.
            my $r = $context->{sock}->shutdown(1);
            ok($r, 'shutdown the socket successfully');
            $context->{sent_fin} = 1;
            $new_events &= ~UV_WRITABLE;
        }
    }

    my $all_done = 0;
    if ($^O ne 'aix') {
        if ($events & UV_DISCONNECT) {
            $context->{got_disconnect} = 1;
            ++$disconnects;
            $new_events &= ~UV_DISCONNECT;
        }
        $all_done = 1 if ($context->{got_fin} && $context->{sent_fin} && $context->{got_disconnect});
    }
    else {
        $all_done = 1 if ($context->{got_fin} && $context->{sent_fin});
    }

    if ($all_done) {
        # Sent and received FIN. Close and destroy context.
        $context->{sock}->close();
        destroy_connection_context($context);
        $context->{events} = 0;
    }
    elsif ($new_events != $context->{events}) {
        # Poll mask changed. Call uv_poll_start again.
        $context->{events} = $new_events;
        $handle->start($new_events, \&connection_poll_cb);
    }

    # Assert that uv_is_active works correctly for poll handles.
    if ($context->{events} != 0) {
        is($handle->active(), 1, 'handle is active');
    }
    else {
        is($handle->active(), 0, 'handle is closed');
    }
}


sub delay_timer_cb {
    my $timer = shift;
    my $context = $timer->data;

    # Timer should auto stop.
    is($timer->active(), 0, 'Timer is not active');

    # Add the requested events to the poll mask.
    ok($context->{delayed_events} != 0, 'we have delayed events');
    $context->{events} |= $context->{delayed_events};
    $context->{delayed_events} = 0;

    my $r = $context->{poll_handle}->start($context->{events}, \&connection_poll_cb);
    is($r, 0, 'started the poll successfully');
}


sub create_server_context {
    my $sock = shift;
    my $context = _server_context_new();

    $context->{sock} = $sock;
    $context->{connections} = 0;

    $context->{poll_handle} = UV::Poll->new(fileno($sock));
    isa_ok($context->{poll_handle}, 'UV::Poll', 'Got a new Poll');
    $context->{poll_handle}->data($context);
    return $context;
}


sub server_close_cb {
    my $handle = shift;
    $handle->data(undef);
}


sub destroy_server_context {
    my $context = shift;
    $context->{poll_handle}->close(\&server_close_cb);
}


sub server_poll_cb {
    my ($handle, $status, $events) = @_;
    my $server_context = $handle->data();

    my $sock = $server_context->{sock}->accept();
    ok(defined($sock), 'Got a new socket');

    my $connection_context = create_connection_context($sock, 1);
    $connection_context->{events} = UV_READABLE | UV_WRITABLE | UV_DISCONNECT;
    my $r = $connection_context->{poll_handle}->start(UV_READABLE | UV_WRITABLE | UV_DISCONNECT, \&connection_poll_cb);
    is($r, 0, 'poll handle started');

    if (++$server_context->{connections} == NUM_CLIENTS) {
        $server_context->{sock}->close();
        destroy_server_context($server_context);
    }
}


sub start_server {
    my $sock = IO::Socket::INET->new(
        Type=>SOCK_STREAM,
        LocalAddr => '127.0.0.1',
        # ReusePort => 1,
        Blocking => 0,
        Proto => Socket::IPPROTO_IP,
        Listen => 100,
    );
    ok(defined($sock), 'server_start: IO::Socket::INET defined');
    ok( !$@, 'server_start: got a good socket');

    $TEST_PORT = $sock->sockport;

    my $context = create_server_context($sock);

    my $r = $context->{poll_handle}->start(UV_READABLE, \&server_poll_cb);
    is($r, 0, 'server_start: started the poll');
}

my $cli_num=0;
sub start_client {
    my $sock = IO::Socket::INET->new(
        Type=>SOCK_STREAM,
        PeerAddr => '127.0.0.1',
        PeerPort => $TEST_PORT,
        # ReusePort => 1,
        Blocking => 0,
        Proto => Socket::IPPROTO_IP,
    );
    ok(defined($sock), 'start_client: IO::Socket::INET defined');
    ok( !$@, 'start_client: got a good socket');
    my $context = create_connection_context($sock, 0);
    $context->{events} = UV_READABLE | UV_WRITABLE | UV_DISCONNECT;
    $context->{cli_num} = ++$cli_num;

    my $r = $context->{poll_handle}->start(UV_READABLE | UV_WRITABLE | UV_DISCONNECT, \&connection_poll_cb);
    is($r, 0, 'start_client: started the poll');
}


sub start_poll_test {
    $closed_connections = 0;
    $valid_writable_wakeups = 0;
    $spurious_writable_wakeups = 0;
    $disconnects = 0;
    start_server();
    start_client() for (0 .. NUM_CLIENTS-1);

    is(UV::Loop->default_loop()->run(), 0, 'default loop run');

    # Assert that at most five percent of the writable wakeups was spurious.
    ok($spurious_writable_wakeups == 0 ||
        ($valid_writable_wakeups + $spurious_writable_wakeups) /
        $spurious_writable_wakeups > 20, 'at most five percent');

    is($closed_connections, NUM_CLIENTS * 2, 'closed cons correct');

    if ($^O eq 'aix') {
        is($disconnects, NUM_CLIENTS * 2, 'disconnects on aix correct');
    }

    _cleanup_loop(UV::Loop->default_loop());
}


subtest 'poll_duplex' => sub {
    $test_mode = DUPLEX;
    start_poll_test();
};


subtest 'poll_unidirectional' => sub {
    $test_mode = UNIDIRECTIONAL;
    start_poll_test();
};


# Windows won't let you open a directory so we open a file instead.
# * OS X lets you poll a file so open the $PWD instead.  Both fail
# * on Linux so it doesn't matter which one we pick.  Both succeed
# * on FreeBSD, Solaris and AIX so skip the test on those platforms.
subtest 'poll_bad_fdtype' => sub {
    plan skip_all => 'Will not fail on *BSD' if $^O =~ /bsd/;
    plan skip_all => 'Will not fail on solaris' if $^O =~ /sun|solaris/;
    plan skip_all => 'Will not fail on aix' if $^O =~ /aix/;
    plan skip_all => 'Will not fail on cygwin/msys' if $^O =~ /cywin|msys/;

    my $fd;
    if (WINLIKE()) {
        open($fd, '<', "$FindBin::Bin/05-poll.t");
    }
    else {
        open($fd, "<", $FindBin::Bin);
    }
    ok($fd != -1, 'good socket');

    my ($poll_handle, $err);
    try {
        $poll_handle = UV::Poll->new($fd);
    }
    catch {
        $err = $_;
    };
    # diag($err);
    ok(!$poll_handle, 'did not get a poll handle');
    ok($err, 'Got an error');
    _cleanup_loop(UV::Loop->default_loop());
};


subtest 'poll_nested_epoll' => sub {
    my $err;
    try { require IO::Epoll; } catch { $err = $_; };
    plan skip_all => 'Linux-only tests' if WINLIKE;
    plan skip_all => 'IO::Epoll not present' if $err;

    my $fd = IO::Epoll::epoll_create(1);
    ok($fd != -1, 'good socket');

    my $poll_handle = UV::Poll->new($fd);
    isa_ok($poll_handle, 'UV::Poll', 'Got a new UV::Poll');
    is($poll_handle->start(UV_READABLE, \&abort), 0, 'poll started');
    isnt(UV::Loop->default_loop()->run(UV::Loop::UV_RUN_NOWAIT), 0, 'default loop run');

    $poll_handle->close(undef);
    is(UV::Loop->default_loop()->run(), 0, 'default loop run');
    POSIX::close($fd);
    _cleanup_loop(UV::Loop->default_loop());
};


subtest 'poll_nested_kqueue' => sub {
    my $err;
    try { require IO::KQueue; } catch { $err = $_; };
    plan skip_all => 'IO::KQueue not present' if $err;

    my $sock = IO::Socket::INET->new(Type => SOCK_STREAM, Blocking => 0);

    my $kq = IO::KQueue->new();
    no strict 'subs';
    $kq->EV_SET(fileno($sock), IO::KQueue::EVFILT_READ, IO::KQueue::EV_ADD, 0, 5);
    use strict 'subs';

    ok($sock != -1, 'good socket');

    my $poll_handle = UV::Poll->new(fileno($sock));
    isa_ok($poll_handle, 'UV::Poll', 'Got a new UV::Poll');
    is($poll_handle->start(UV_READABLE, \&abort), 0, 'poll started');
    isnt(UV::Loop->default_loop()->run(UV::Loop::UV_RUN_NOWAIT), 0, 'default loop run');

    $poll_handle->close(undef);
    is(UV::Loop->default_loop()->run(), 0, 'default loop run');
    $sock->close();
    _cleanup_loop(UV::Loop->default_loop());
};

done_testing();
