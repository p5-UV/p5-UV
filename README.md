# NAME

UV - Perl interface to libuv

# SYNOPSIS

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

# DESCRIPTION

This module provides an interface to [libuv](http://libuv.org). We will try to
document things here as best as we can, but we also suggest you look at the
[libuv docs](http://docs.libuv.org) directly for more details on how things
work.

Event loops that work properly on all platforms. YAY!

# CONSTANTS

## ERROR CONSTANTS

### UV\_EBUSY

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

The following functions are available:

## default\_loop

    my $loop = UV::default_loop();
    # You can also get it with the UV::Loop methods below:
    my $loop = UV::Loop->default_loop();
    my $loop = UV::Loop->default();
    # Passing a true value as the first arg to the UV::Loop constructor
    # will also return the default loop
    my $loop = UV::Loop->new(1);

Returns the default loop (which is a singleton object). This module already
creates the default loop and you get access to it with this method.

## hrtime

Get the current Hi-Res time (`uint64_t`).

# AUTHOR

Daisuke Murase <`typester@cpan.org`>

# CONTRIBUTORS

Chase Whitener <`capoeirab@cpan.org`>

# COPYRIGHT AND LICENSE

Copyright 2012, Daisuke Murase.

This library is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.
