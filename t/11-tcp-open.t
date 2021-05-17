use strict;
use warnings;

use UV::Loop ();
use UV::TCP ();

use Test::More;

use IO::Socket::INET;
use Socket;

# TODO: This test might not work on MSWin32. We might need to find a different
#   implementation, or just skip it?

sub socketpair_inet
{
    my ($rd, $wr);

    # Maybe socketpair(2) can do it?
    ($rd, $wr) = IO::Socket->socketpair(AF_INET, SOCK_STREAM, 0)
        and return ($rd, $wr);

    # If not, go the long way round
    note "Using 'manual' socket pair";
    my $listen = IO::Socket::INET->new(
        #LocalHost => "127.0.0.1",
        LocalHost => "localhost",
        LocalPort => 0,
        Listen    => 1,
    ) or die "Cannot listen - $@";

    $rd = IO::Socket::INET->new(
        PeerHost => $listen->sockhost,
        PeerPort => $listen->sockport,
    ) or die "Cannot connect - $@";

    $wr = $listen->accept or die "Cannot accept - $!";

    return ($rd, $wr);
}

# Launch watchdog on Windows in background
if( $^O eq 'MSWin32' ) {
    my $ppid = $$;
    my $child= system(1, $^X,'-e',"sleep 5; kill KILL => $ppid");
    if( !$child ) {
        diag "Could not launch watchdog: $^E";
    } else {
            note "Watchdog started (5 seconds)";
    };
    END {
        if( $child ) {
            kill KILL => $child
                or diag "Could not kill watchdog: $^E";
            note "Watchdog removed";
        }
    }
}

# write, then read
{
    my ($rd, $wr) = socketpair_inet();

    my $tcp = UV::TCP->new;
    isa_ok($tcp, 'UV::TCP');
note "Opening (existing) socket " . $rd->fileno;
    $tcp->open($rd);
note "Socket opened, setting up callback";

    my $read_cb_called;
    $tcp->on(read => sub {
        my ($self, $status, $buf) = @_;
        $read_cb_called++;

        is($buf, "data to read", 'data was read from tcp socket');

        $self->close;
    });
    
    note "Socket opened, writing data";
    my $ret;
    for my $word ('', 'data to', ' read') {
        note "Writing '$word'";
        $wr->syswrite($word);
        #$wr->flush();
        
        if( ! $ret ) {
            note "Calling ->read_start";
            $ret = $tcp->read_start;
            note "Calling ->read_start returns $tcp ($ret)";
        };
    };
    is($ret, $tcp, '$tcp->read_start returns $tcp');

    UV::Loop->default->run;
    ok($read_cb_called, 'read callback was called when data is already pending');
}

# read, then write, currently fails
{
    my ($rd, $wr) = socketpair_inet();

    my $tcp = UV::TCP->new;
    isa_ok($tcp, 'UV::TCP');
note "Opening (existing) socket " . $rd->fileno;
    $tcp->open($rd);
note "Socket opened, setting up callback";

    my $read_cb_called;
    $tcp->on(read => sub {
        my ($self, $status, $buf) = @_;
        $read_cb_called++;

        is($buf, "data to read", 'data was read from tcp socket');

        $self->close;
    });
    note "Socket opened, writing data";
    note "Calling ->read_start";
    my $ret = $tcp->read_start;
    note "Calling ->read_start returns $tcp ($ret)";
    is($ret, $tcp, '$tcp->read_start returns $tcp');

note "Socket opened, writing data";
    $wr->syswrite("data to read");

    UV::Loop->default->run;
    ok($read_cb_called, 'read callback was called after data became pending');
}

# write
{
    my ($rd, $wr) = socketpair_inet();

    my $tcp = UV::TCP->new;

    $tcp->open($wr);

    my $write_cb_called;
    my $req = $tcp->write("data to write", sub { $write_cb_called++ } );

    UV::Loop->default->run;
    ok($write_cb_called, 'write callback was called');

    $rd->sysread(my $buf, 8192);
    is($buf, "data to write", 'data was written to tcp socket');

    # both libuv and perl want to close(2) this filehandle. Perl will warn if
    # it gets  EBADF
    { no warnings; undef $wr; }
}

done_testing();
