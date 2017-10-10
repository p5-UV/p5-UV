package UV;

our $VERSION = '1.000003';
our $XS_VERSION = $VERSION;
$VERSION = eval $VERSION;

use strict;
use warnings;
use Exporter qw(import);
require XSLoader;

XSLoader::load('UV', $XS_VERSION);

our @EXPORT_OK;
# The XS code adds the constants to EXPORT_OK
push @EXPORT_OK, qw(default_loop err_name hrtime strerr translate_sys_error);

# Loop
use UV::Loop ();
# Handles
use UV::Check ();
use UV::Idle ();
use UV::Poll ();
use UV::Prepare ();
use UV::Timer ();

sub default_loop { return UV::Loop->default_loop(); }

1;

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

=head1 HELP NEEDED

If you are a C/XS developer, I'm pleading for help. While the test cases so far
function as expected, some design decisions I've made up to this point have
become somewhat untenable.

Please submit PRs, yell at me on IRC, email me, call me, contact me by any means
available to you to help me fix this and get the entirety of the libuv project
ready for Perl use.

Thanks!!

=head1 CONSTANTS

=head2 VERSION CONSTANTS

=head3 UV_VERSION_MAJOR

=head3 UV_VERSION_MINOR

=head3 UV_VERSION_PATCH

=head3 UV_VERSION_IS_RELEASE

=head3 UV_VERSION_SUFFIX

=head3 UV_VERSION_HEX

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

=head2 err_name

    my $error_name = UV::err_name(UV::UV_EAI_BADFLAGS);
    say $error_name; # EAI_BADFLAGS

The L<err_name|http://docs.libuv.org/en/v1.x/errors.html#c.uv_err_name>
function returns the error name for the given error code. Leaks a few bytes of
memory when you call it with an unknown error code.

In libuv errors are negative numbered constants. As a rule of thumb, whenever
there is a status parameter, or an API functions returns an integer, a negative
number will imply an error.

When a function which takes a callback returns an error, the callback will
never be called.

=head2 hrtime

    my $uint64_t = UV::hrtime();

Get the current Hi-Res time (C<uint64_t>).

=head2 strerror

    my $error = UV::strerror(UV::UV_EAI_BADFLAGS);
    say $error; # bad ai_flags value

The L<strerror|http://docs.libuv.org/en/v1.x/errors.html#c.uv_strerror>
function returns the error message for the given error code. Leaks a few bytes
of memory when you call it with an unknown error code.

In libuv errors are negative numbered constants. As a rule of thumb, whenever
there is a status parameter, or an API functions returns an integer, a negative
number will imply an error.

When a function which takes a callback returns an error, the callback will
never be called.

=head2 version

    my $int = UV::version();

The L<version|http://docs.libuv.org/en/v1.x/version.html#c.uv_version> function
returns C<UV::UV_VERSION_HEX>, the libuv version packed into a single integer.
8 bits are used for each component, with the patch number stored in the 8 least
significant bits. E.g. for libuv 1.2.3 this would be C<0x010203>.

=head2 version_string

    say UV::version_string();
    # 1.13.1

The L<version_string|http://docs.libuv.org/en/v1.x/version.html#c.uv_version_string>
function returns the libuv version number as a string. For non-release versions
the version suffix is included.

=head1 AUTHOR

Chase Whitener <F<capoeirab@cpan.org>>

=head1 AUTHOR EMERITUS

Daisuke Murase <F<typester@cpan.org>>

=head1 COPYRIGHT AND LICENSE

Copyright 2012, Daisuke Murase.

This library is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.

=cut
