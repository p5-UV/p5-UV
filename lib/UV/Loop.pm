package UV::Loop;

our $VERSION = '1.000006';

use strict;
use warnings;
use Carp ();
use Devel::GlobalDestruction ();
use Exporter qw(import);
use Scalar::Util ();
use UV ();

our @EXPORT_OK = (@UV::Loop::EXPORT_XS,);

# simple function to ensure we've been given a UV::Loop
# this is useful in new Handle construction
sub _is_a_loop {
    my $loop = shift;
    return undef unless $loop;
    return undef unless ref($loop) && Scalar::Util::blessed($loop);
    return undef unless $loop->isa('UV::Loop');
    return 1;
}

sub new {
    my $self = bless {}, shift;
    my $args = UV::_parse_args(@_);
    $self->on('walk', $args->{on_walk});
    $self->{data} = $args->{data};
    $self->{_default} = (exists($args->{_default}) && $args->{_default})? 1: 0;
    my $err = do { #catch
        local $@;
        eval { $self->_create($self->{_default}); 1; }; #try
        $@;
    };
    Carp::croak($err) if $err; # throw
    return $self;
}

sub DESTROY {
    my $self = shift;
    my $class = Scalar::Util::blessed($self);
    my $def = $self->is_default();

    if ($self->_has_struct()) {
        my $err = do { # catch
            local $@;
            eval { $self->_destruct($self->is_default()); 1; }; # try
            $@;
        };
        warn $err if $err;
    }
    if (Devel::GlobalDestruction::in_global_destruction() && $def && $class) {
        no strict 'refs';
        undef(${"$class\::_default_loop"});
    }
}

sub close {
    my $self = shift;
    return UV::UV_ENOSYS unless $self->_has_struct();
    return $self->_close();
}

# Return the singleton uv_default_loop
sub default {
    my $class = shift;
    my $default_loop;
    {
        no strict 'refs';
        $default_loop = \${"$class\::_default_loop"};
    }
    unless (defined($$default_loop) && ${$default_loop}->_has_struct) {
        $$default_loop = $class->new(@_, _default => 1);
    }
    return $$default_loop;
}

sub default_loop { return shift->default(); }

sub is_default {
    my $self = shift;
    return 1 if $self->{_default};
    return 0;
}

sub on {
    my $self = shift;
    my $event = lc(shift || '');
    return $self unless $event && $event eq 'walk';
    return $self->{"_on_$event"} unless @_;
    my $cb = ($_[-1] && ref($_[-1]) eq 'CODE')? pop: undef;
    $self->{"_on_$event"} = $cb;
    return $self;
}

sub walk {
    my $self = shift;
    return unless $self->alive();
    $self->on('walk', @_) if @_; # set the callback ahead of time if exists
    $self->_walk();
}

1;

__END__

=encoding utf8

=head1 NAME

UV::Loop - Looping with libuv

=head1 SYNOPSIS

  #!/usr/bin/env perl
  use strict;
  use warnings;

  use UV;

  # A new, non-default loop
  my $loop = UV::Loop->new();

  # a new loop with the walk callback provided:
  my $loop = UV::Loop->new(
    on_walk => sub {say "walking!"},
  );

  # A new default loop instance (Singleton)
  my $loop = UV::Loop->default_loop(); # singleton constructor
  my $loop = UV::Loop->default(); # singleton constructor

  # run a loop with one of three options:
  # UV_RUN_DEFAULT, UV_RUN_ONCE, UV_RUN_NOWAIT
  $loop->run(); # runs with UV_RUN_DEFAULT
  $loop->run(UV::Loop::UV_RUN_DEFAULT); # explicitly state UV_RUN_DEFAULT
  $loop->run(UV::Loop::UV_RUN_ONCE);
  $loop->run(UV::Loop::UV_RUN_NOWAIT);


=head1 DESCRIPTION

This module provides an interface to
L<libuv's loop|http://docs.libuv.org/en/v1.x/loop.html>. We will try to
document things here as best as we can, but we also suggest you look at the
L<libuv docs|http://docs.libuv.org> directly for more details on how things
work.

Event loops that work properly on all platforms. YAY!

=head1 CONSTANTS

=head2 RUN MODE CONSTANTS

=head3 UV_RUN_DEFAULT

=head3 UV_RUN_NOWAIT

=head3 UV_RUN_ONCE

=head2 CONFIGURE CONSTANTS

=head3 SIGPROF

=head3 UV_LOOP_BLOCK_SIGNAL

=head1 EVENTS

L<UV::Loop> makes the following extra events available.

=head2 walk

    $loop->on("walk", sub { say "We are walking!"});
    $loop->on("walk", sub {
        # the handle instance this event fired on and the buffer size in use
        my ($handle) = @_;
        say "walking over active handles";
    });

The L<walk|http://docs.libuv.org/en/v1.x/loop.html#c.uv_walk_cb> callback
fires when a C<< $loop->walk() >> method gets called.

=head1 METHODS

L<UV::Loop> makes the following methods available.

=head2 new

    my $loop = UV::Loop->new(
        on_walk => sub {say "walking!"},
    );
    my $default_loop = UV::Loop->default_loop();
    my $default_loop = UV::Loop->default();

This constructor either returns the default loop (singleton object), or creates
a new event loop and
L<initializes|http://docs.libuv.org/en/v1.x/loop.html#c.uv_loop_init> it.

Please look at the L<documentation|http://docs.libuv.org/en/v1.x/loop.html>
from libuv.

=head2 alive

    my $int = $loop->alive();

The L<alive|http://docs.libuv.org/en/v1.x/loop.html#c.uv_loop_alive> method
returns a non-zero value if there are active handles or requests in the loop.

=head2 backend_fd

    my $int = $loop->backend_fd();

The L<backend_fd|http://docs.libuv.org/en/v1.x/loop.html#c.uv_backend_fd>
method returns the backend file descriptor. Only C<kqueue>, C<epoll> and
C<event ports> are supported.

This can be used in conjunction with L<UV::Loop/"run"> and C<UV_RUN_NOWAIT> to
poll in one thread and run the event loop's callbacks in another.

B<* Note:> Embedding a C<kqueue fd> in another C<kqueue pollset> doesn't work
on all platforms. It's not an error to add the C<fd> but it never generates
events.

=head2 backend_timeout

    my $int = $loop->backend_timeout();

The L<backend_timeout|http://docs.libuv.org/en/v1.x/loop.html#c.uv_backend_timeout>
method returns the poll timeout. The return value is in milliseconds, or C<-1>
for no timeout.

=head2 close

    $loop->close();

The L<close|http://docs.libuv.org/en/v1.x/loop.html#c.uv_loop_close> method
releases all internal loop resources. Call this method only when the loop has
finished executing and all open handles and requests have been closed, or it
will return C<UV::UV_EBUSY>. After this method returns, the user can free the
memory allocated for the loop.

=head2 configure

    my $int = $loop->configure();

The L<configure|http://docs.libuv.org/en/v1.x/loop.html#c.uv_loop_configure>
method sets additional loop options. You should normally call this before the
first call to L<UV::Loop/"run"> unless mentioned otherwise.

Returns C<0> on success or a C<UV/"CONSTANTS"> error code on failure. Be
prepared to handle C<UV::UV_ENOSYS>; it means the loop option is not supported
by the platform.

Supported options:

=over

=item

C<UV_LOOP_BLOCK_SIGNAL>: Block a signal when polling for new events. The second
argument to C<< $loop->configure >> is the signal number.

This operation is currently only implemented for C<SIGPROF> signals, to
suppress unnecessary wakeups when using a sampling profiler. Requesting other
signals will fail with C<UV::UV_EINVAL>.

=back

=head2 default

    # this is a singleton constructor. you'll get the same instance each time
    my $default_loop = UV::Loop->default();

A singleton method to get the default loop instance.

=head2 default_loop

    # this is a singleton constructor. you'll get the same instance each time
    my $default_loop = UV::Loop->default_loop();

A singleton method to get the default loop instance.

=head2 is_default

    # lets us know if this loop is the default loop for this context
    my $bool = $loop->is_default();

A read-only method to let us know if we're dealing with the default loop.

=head2 now

    my $uint64_t = $loop->now();

The L<now|http://docs.libuv.org/en/v1.x/loop.html#c.uv_now> method returns the
current timestamp in milliseconds. The timestamp is cached at the start of the
event loop tick, see L<UV::Loop/"update_loop"> for details and rationale.

The timestamp increases monotonically from some arbitrary point in time. Don't
make assumptions about the starting point, you will only get disappointed.

B<* Note:> Use L<UV/"hrtime"> if you need sub-millisecond granularity.

=head2 on

    # set a walk event callback to print the handle's data attribute
    $loop->on('walk', sub {
        my $hndl = shift;
        say $hndl->data();
        say "walking!"
    });

    # clear out the walk event callback for the loop
    $loop->on(walk => undef);
    $loop->on(walk => sub {});

The C<on> method allows you to subscribe to L<UV::Loop/"EVENTS"> emitted by
any UV::Loop.

=head2 run

    # use UV_RUN_DEFAULT by default
    my $int = $loop->run();
    # or, explicitly use it:
    my $int = $loop->run(UV::Loop::UV_RUN_DEFAULT);
    # run in UV_RUN_NOWAIT mode
    my $int = $loop->run(UV::Loop::UV_RUN_NOWAIT);
    # run in UV_RUN_ONCE mode
    my $int = $loop->run(UV::Loop::UV_RUN_ONCE);

The L<run|http://docs.libuv.org/en/v1.x/loop.html#c.uv_run> method runs the
event loop. It will act differently depending on the specified mode:

=over 4

=item

C<UV_RUN_DEFAULT> Runs the event loop until there are no more active and
referenced handles or requests. Returns non-zero if L<UV::Loop/"stop"> was
called and there are still active handles or requests. Returns zero in all other
cases.

=item

C<UV_RUN_NOWAIT> Poll for i/o once but don't block if there are no pending
callbacks. Returns zero if done (no active handles or requests left), or
non-zero if more callbacks are expected (meaning you should run the event loop
again sometime in the future).

=item

C<UV_RUN_ONCE> Poll for i/o once. Note that this function blocks if there are
no pending callbacks. Returns zero when done (no active handles or requests
left), or non-zero if more callbacks are expected (meaning you should run the
event loop again sometime in the future).

=back

=head2 stop

    $loop->stop();

The L<stop|http://docs.libuv.org/en/v1.x/loop.html#c.uv_stop> method stops the
event loop, causing L<UV::Loop/"run"> to end as soon as possible. This will
happen not sooner than the next loop iteration. If this function was called
before blocking for i/o, the loop won't block for i/o on this iteration.

=head2 update_time

    $loop->update_time();

The L<update_time|http://docs.libuv.org/en/v1.x/loop.html#c.uv_update_time>
method updates the event loop's concept of L<UV::Loop/"now">. Libuv caches the
current time at the start of the event loop tick in order to reduce the number
of time-related system calls.

You won't normally need to call this method unless you have callbacks that
block the event loop for longer periods of time, where "longer" is somewhat
subjective but probably on the order of a millisecond or more.

=head2 walk

    # although you can do it, calling ->walk() without a callback is pretty
    # useless.
    # call with no callback
    $loop->walk();
    $loop->walk(undef);
    $loop->walk(sub {});

    # instead, let's walk the loop and cleanup any handles attached and then
    # completely close the loop.
    $loop->walk(sub {
        my $handle = shift;
        # check to make sure the handle can stop
        $handle->stop() if $handle->can('stop');
        $handle->close() unless $handle->closing();
        $loop->run(UV::Loop::UV_RUN_DEFAULT);
        $loop->close();
    });

The L<walk|http://docs.libuv.org/en/v1.x/loop.html#c.uv_walk> method will
C<walk> the list of handles and fire off the callback supplied.

This is an excellent way to ensure your loop is completely cleaned up.


=head1 AUTHOR

Chase Whitener <F<capoeirab@cpan.org>>

=head1 AUTHOR EMERITUS

Daisuke Murase <F<typester@cpan.org>>

=head1 COPYRIGHT AND LICENSE

Copyright 2012, Daisuke Murase.

This library is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.

=cut
