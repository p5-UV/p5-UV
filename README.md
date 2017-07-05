# NAME

UV - Some utility functions from libUV.

# SYNOPSIS

    #!/usr/bin/env perl
    use strict;
    use warnings;
    use feature ':5.14';

    use UV;
    use Syntax::Keyword::Try;

# DESCRIPTION

This module provides access to a few of the functions in the miscellaneous
[libUV](http://docs.libuv.org/en/v1.x/misc.html) utilities. While it's extremely
unlikely, all functions here can throw an exception on error unless specifically
stated otherwise in the function's description.

# CONSTANTS

## HANDLE TYPE CONSTANTS

### UV\_ASYNC

### UV\_CHECK

### UV\_FILE

### UV\_FS\_EVENT

### UV\_FS\_POLL

### UV\_HANDLE

### UV\_HANDLE\_TYPE\_MAX

### UV\_IDLE

### UV\_NAMED\_PIPE

### UV\_POLL

### UV\_PREPARE

### UV\_PROCESS

### UV\_SIGNAL

### UV\_STREAM

### UV\_TCP

### UV\_TIMER

### UV\_TTY

### UV\_UDP

### UV\_UNKNOWN\_HANDLE

# FUNCTIONS

## hrtime

Get the current Hi-Res time

# AUTHOR

Daisuke Murase <`typester@cpan.org`>

# CONTRIBUTORS

Chase Whitener <`capoeirab@cpan.org`>

# COPYRIGHT AND LICENSE

Copyright 2012, Daisuke Murase.

This library is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.
