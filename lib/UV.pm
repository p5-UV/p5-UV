package UV;

our $VERSION = '0.001';
our $XS_VERSION = $VERSION;
$VERSION = eval $VERSION;

use strict;
use warnings;
use Exporter qw(import);
require XSLoader;

our @EXPORT_OK  = qw(
);

XSLoader::load('UV', $XS_VERSION);

1;
__END__

=encoding utf8

=head1 NAME

UV - Some utility functions from libUV.

=head1 SYNOPSIS

  #!/usr/bin/env perl
  use strict;
  use warnings;
  use feature ':5.14';

  use UV;
  use Syntax::Keyword::Try;


=head1 DESCRIPTION

This module provides access to a few of the functions in the miscellaneous
L<libUV|http://docs.libuv.org/en/v1.x/misc.html> utilities. While it's extremely
unlikely, all functions here can throw an exception on error unless specifically
stated otherwise in the function's description.

=head1 CONSTANTS

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

=head2 hrtime

Get the current Hi-Res time

=head1 COPYRIGHT AND LICENSE

Copyright 2017, Chase Whitener.

This library is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.

=cut
