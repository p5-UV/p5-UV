package UV;

our $VERSION = '1.000';
our $XS_VERSION = $VERSION;
$VERSION = eval $VERSION;

use strict;
use warnings;
use Exporter qw(import);
require XSLoader;

XSLoader::load('UV', $XS_VERSION);

our @EXPORT_OK  = qw(
    UV_E2BIG UV_EACCES UV_EADDRINUSE UV_EADDRNOTAVAIL UV_EAFNOSUPPORT UV_EAGAIN
    UV_EAI_ADDRFAMILY UV_EAI_AGAIN UV_EAI_BADFLAGS" UV_EAI_BADHINTS
    UV_EAI_CANCELED UV_EAI_FAIL UV_EAI_FAMILY UV_EAI_MEMORY UV_EAI_NODATA
    UV_EAI_NONAME UV_EAI_OVERFLOW UV_EAI_PROTOCOL UV_EAI_SERVICE
    UV_EAI_SOCKTYPE UV_EALREADY UV_EBADF UV_EBUSY UV_ECANCELED UV_ECHARSET
    UV_ECONNABORTED UV_ECONNREFUSED UV_ECONNRESET UV_EDESTADDRREQ UV_EEXIST
    UV_EFAULT UV_EFBIG UV_EHOSTUNREACH UV_EINTR UV_EINVAL UV_EIO UV_EISCONN
    UV_EISDIR UV_ELOOP UV_EMFILE UV_EMSGSIZE UV_ENAMETOOLONG UV_ENETDOWN
    UV_ENETUNREACH UV_ENFILE UV_ENOBUFS UV_ENODEV UV_ENOENT UV_ENOMEM
    UV_ENONET UV_ENOPROTOOPT UV_ENOSPC UV_ENOSYS UV_ENOTCONN UV_ENOTDIR
    UV_ENOTEMPTY UV_ENOTSOCK UV_ENOTSUP UV_EPERM UV_EPIPE UV_EPROTO
    UV_EPROTONOSUPPORT UV_EPROTOTYPE UV_ERANGE UV_EROFS UV_ESHUTDOWN UV_ESPIPE
    UV_ESRCH UV_ETIMEDOUT UV_ETXTBSY UV_EXDEV UV_UNKNOWN UV_EOF UV_ENXIO
    UV_EMLINK
);

# make sure all sub-classes of uv_handle_t are thought of as such
@UV::Async::ISA =
@UV::Check::ISA =
@UV::FSEvent::ISA =
@UV::FSPoll::ISA =
@UV::Idle::ISA =
@UV::NamedPipe::ISA =
@UV::Poll::ISA =
@UV::Prepare::ISA =
@UV::Process::ISA =
@UV::Stream::ISA =
@UV::TCP::ISA =
@UV::Timer::ISA =
@UV::TTY::ISA =
@UV::UDP::ISA =
@UV::Signal::ISA =
@UV::File::ISA =
    "UV::Handle";
1;

# load up the default loop
default_loop() or die 'UV: cannot initialise libUV backend.';

__END__

=encoding utf8

=head1 NAME

UV - Perl interface to libuv

=head1 SYNOPSIS

  #!/usr/bin/env perl
  use strict;
  use warnings;

  use UV;

  # hi-resolution time
  my $hi_res_time = UV::hrtime();

  # A new loop
  my $loop = UV::Loop->new();

  # default loop
  my $loop = UV::Loop->default_loop(); # convenience constructor
  my $loop = UV::Loop->new(1); # Tell the constructor you want the default loop

  # run a loop with one of three options:
  # UV_RUN_DEFAULT, UV_RUN_ONCE, UV_RUN_NOWAIT
  $loop->run(); # runs with UV_RUN_DEFAULT
  $loop->run(UV::Loop::UV_RUN_DEFAULT); # explicitly state UV_RUN_DEFAULT
  $loop->run(UV::Loop::UV_RUN_ONCE);
  $loop->run(UV::Loop::UV_RUN_NOWAIT);


=head1 DESCRIPTION

This module provides an interface to L<libuv|http://libuv.org>. We will try to
document things here as best as we can, but we also suggest you look at the
L<libuv docs|http://docs.libuv.org> directly for more details on how things
work.

Event loops that work properly on all platforms. YAY!

=head1 CONSTANTS

=head2 ERROR CONSTANTS

=head3 UV_E2BIG

Argument list too long

=head3 UV_EACCES

Permission denied

=head3 UV_EADDRINUSE

Address already in use

=head3 UV_EADDRNOTAVAIL

Address not available

=head3 UV_EAFNOSUPPORT

Address family not supported

=head3 UV_EAGAIN

Resource temporarily unavailable

=head3 UV_EAI_ADDRFAMILY

Address family not supported

=head3 UV_EAI_AGAIN

Temporary failure

=head3 UV_EAI_BADFLAGS

Bad ai_flags value

=head3 UV_EAI_BADHINTS

Invalid value for hints

=head3 UV_EAI_CANCELED

Request canceled

=head3 UV_EAI_FAIL

Permanent failure

=head3 UV_EAI_FAMILY

ai_family not supported

=head3 UV_EAI_MEMORY

Out of memory

=head3 UV_EAI_NODATA

No address

=head3 UV_EAI_NONAME

Unknown node or service

=head3 UV_EAI_OVERFLOW

Argument buffer overflow

=head3 UV_EAI_PROTOCOL

Resolved protocol is unknown

=head3 UV_EAI_SERVICE

Service not available for socket type

=head3 UV_EAI_SOCKTYPE

Socket type not supported

=head3 UV_EALREADY

Connection already in progress

=head3 UV_EBADF

Bad file descriptor

=head3 UV_EBUSY

Resource busy or locked

=head3 UV_ECANCELED

Operation canceled

=head3 UV_ECHARSET

Invalid Unicode character

=head3 UV_ECONNABORTED

Software caused connection abort

=head3 UV_ECONNREFUSED

Connection refused

=head3 UV_ECONNRESET

Connection reset by peer

=head3 UV_EDESTADDRREQ

Destination address required

=head3 UV_EEXIST

File already exists

=head3 UV_EFAULT

Bad address in system call argument

=head3 UV_EFBIG

File too large

=head3 UV_EHOSTUNREACH

Host is unreachable

=head3 UV_EINTR

Interrupted system call

=head3 UV_EINVAL

Invalid argument

=head3 UV_EIO

i/o error

=head3 UV_EISCONN

Socket is already connected

=head3 UV_EISDIR

Illegal operation on a directory

=head3 UV_ELOOP

Too many symbolic links encountered

=head3 UV_EMFILE

Too many open files

=head3 UV_EMLINK

Too many links

=head3 UV_EMSGSIZE

Message too long

=head3 UV_ENAMETOOLONG

Name too long

=head3 UV_ENETDOWN

Network is down

=head3 UV_ENETUNREACH

Network is unreachable

=head3 UV_ENFILE

File table overflow

=head3 UV_ENOBUFS

No buffer space available

=head3 UV_ENODEV

No such device

=head3 UV_ENOENT

No such file or directory

=head3 UV_ENOMEM

Not enough memory

=head3 UV_ENONET

Machine is not on the network

=head3 UV_ENOPROTOOPT

Protocol not available

=head3 UV_ENOSPC

No space left on device

=head3 UV_ENOSYS

Function not implemented

=head3 UV_ENOTCONN

Socket is not connected

=head3 UV_ENOTDIR

Not a directory

=head3 UV_ENOTEMPTY

Directory not empty

=head3 UV_ENOTSOCK

Socket operation on non-socket

=head3 UV_ENOTSUP

Operation not supported on socket

=head3 UV_ENXIO

No such device or address

=head3 UV_EOF

End of file

=head3 UV_EPERM

Operation not permitted

=head3 UV_EPIPE

Broken pipe

=head3 UV_EPROTO

Protocol error

=head3 UV_EPROTONOSUPPORT

Protocol not supported

=head3 UV_EPROTOTYPE

Protocol wrong type for socket

=head3 UV_ERANGE

Result too large

=head3 UV_EROFS

Read-only file system

=head3 UV_ESHUTDOWN

Cannot send after transport endpoint shutdown

=head3 UV_ESPIPE

Invalid seek

=head3 UV_ESRCH

No such process

=head3 UV_ETIMEDOUT

Connection timed out

=head3 UV_ETXTBSY

Text file is busy

=head3 UV_EXDEV

Cross-device link not permitted

=head3 UV_UNKNOWN

Unknown error


=head1 FUNCTIONS

The following functions are available:

=head2 default_loop

    my $loop = UV::default_loop();
    # You can also get it with the UV::Loop methods below:
    my $loop = UV::Loop->default_loop();
    my $loop = UV::Loop->default();
    # Passing a true value as the first arg to the UV::Loop constructor
    # will also return the default loop
    my $loop = UV::Loop->new(1);

Returns the default loop (which is a singleton object). This module already
creates the default loop and you get access to it with this method.

=head2 hrtime

    my $uint64_t = UV::hrtime();

Get the current Hi-Res time (C<uint64_t>).

=head1 AUTHOR

Chase Whitener <F<capoeirab@cpan.org>>

=head1 AUTHOR EMERITUS

Daisuke Murase <F<typester@cpan.org>>

=head1 COPYRIGHT AND LICENSE

Copyright 2012, Daisuke Murase.

This library is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.

=cut
