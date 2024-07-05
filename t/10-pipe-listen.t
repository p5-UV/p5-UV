use strict;
use warnings;

use UV::Loop ();
use UV::Pipe ();

use Test::More;

use IO::Socket::UNIX;
use File::Basename;

my $path = basename( $0 ) . ".sock";
my $is_win32 = $^O eq 'MSWin32';

if( $is_win32) {
    $path = "\\\\?\\pipe\\$path";
};

my $pipe = UV::Pipe->new;
isa_ok($pipe, 'UV::Pipe');

$pipe->bind($path);
if( ! $is_win32 ) {
    END { unlink $path if $path; }
};

if( $is_win32) {
    ok(1, "$path exists on the \\\\.\\pipe\\ filesystem");
} else {
    ok(-S $path, 'Path created as a socket');
};

my $connection_cb_called;
sub connection_cb {
    my ($self) = @_;
    $connection_cb_called++;

    my $client = $self->accept;
    my $expected = $is_win32 ? '' : $path;

    isa_ok($client, 'UV::Pipe');
    is($client->getsockname, $expected, 'getsockname returns sockaddr');

    $self->close;
    $client->close;
}

$pipe->listen(5, \&connection_cb);

my $sock;

if( $is_win32 ) {
    $sock  = UV::Pipe->new();
    $sock->connect($path, sub {})
        or die "Cannot connect pipe - $@"; # yes $@
} else {
    $sock  = IO::Socket::UNIX->new(
        Peer => $path,
    ) or die "Cannot connect socket - $@"; # yes $@
};

UV::Loop->default->run;

ok($connection_cb_called, 'connection callback was called');

done_testing();
