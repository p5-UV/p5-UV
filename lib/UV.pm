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

=head3 UV_EBUSY

=head2 HANDLE TYPE CONSTANTS

=head3 UV_ASYNC

=head3 UV_CHECK

=head3 UV_FILE

=head3 UV_FS_EVENT

=head3 UV_FS_POLL

=head3 UV_HANDLE

=head3 UV_HANDLE_TYPE_MAX

=head3 UV_IDLE

=head3 UV_NAMED_PIPE

=head3 UV_POLL

=head3 UV_PREPARE

=head3 UV_PROCESS

=head3 UV_SIGNAL

=head3 UV_STREAM

=head3 UV_TCP

=head3 UV_TIMER

=head3 UV_TTY

=head3 UV_UDP

=head3 UV_UNKNOWN_HANDLE

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

Get the current Hi-Res time (C<uint64_t>).

=head1 AUTHOR

Daisuke Murase <F<typester@cpan.org>>

=head1 CONTRIBUTORS

Chase Whitener <F<capoeirab@cpan.org>>

=head1 COPYRIGHT AND LICENSE

Copyright 2012, Daisuke Murase.

This library is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.

=cut
