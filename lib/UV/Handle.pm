package UV::Handle;

our $VERSION = '1.000';
$VERSION = eval $VERSION;

use strict;
use warnings;
use Exporter qw(import);

use UV;

our @EXPORT_OK  = qw(
    UV_ASYNC UV_CHECK UV_FS_EVENT UV_FS_POLL
    UV_IDLE UV_NAMED_PIPE UV_POLL UV_PREPARE UV_PROCESS
    UV_STREAM UV_TCP UV_TIMER UV_TTY UV_UDP UV_SIGNAL UV_FILE
);

1;

__END__

=encoding utf8

=head1 NAME

UV::Handle - Handles in libuv

=head1 SYNOPSIS

  #!/usr/bin/env perl
  use strict;
  use warnings;

  use UV;

  # Handle is just a base-class for all types of Handles in libuv

  # For example, a UV::Timer
  # A new timer will give initialize against the default loop
  my $timer = UV::Timer->new();

=head1 DESCRIPTION

This module provides an interface to
L<libuv's handle|http://docs.libuv.org/en/v1.x/handle.html>. We will try to
document things here as best as we can, but we also suggest you look at the
L<libuv docs|http://docs.libuv.org> directly for more details on how things
work.

You will likely never use this class directly. You will use the different handle
sub-classes directly. Some of these methods or events will be called or fired
from those sub-classes.

=head1 CONSTANTS

=head2 HANDLE TYPE CONSTANTS

=head3 UV_ASYNC

=head3 UV_CHECK

=head3 UV_FILE

=head3 UV_FS_EVENT

=head3 UV_FS_POLL

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

=head1 EVENTS

L<UV::Handle> makes the following extra events available.

=head2 alloc

    $handle->on("alloc", sub { say "We are allocating!"});
    $handle->on("alloc", sub {
        # the handle instance this event fired on and the buffer size in use
        my ($invocant, $buffer_size) = @_;
        say "A buffer of size $buffer_size was just allocated for us!";
    });

The L<alloc|http://docs.libuv.org/en/v1.x/handle.html#c.uv_alloc_cb> callback
fires when a C<< $handle->read_start() >> or C<< $handle->recv_start() >>
method gets called.

=head2 close

    $handle->on("close", sub { say "We are closing!"});
    $handle->on("close", sub {
        # the handle instance this event fired on
        my $invocant = shift;
        say "The handle is closing";
    });

The L<close|http://docs.libuv.org/en/v1.x/handle.html#c.uv_close_cb> callback
fires when a C<< $handle->close() >> method gets called.

=head1 ATTRIBUTES

L<UV::Handle> implements the following attributes.

=head2 data

    $handle = $handle->data(23); # allows for method chaining.
    $handle = $handle->data("Some stringy stuff");
    $handle = $handle->data(Foo::Bar->new());
    $handle = $handle->data(undef);
    my $data = $handle->data();

The L<data|http://docs.libuv.org/en/v1.x/handle.html#c.uv_handle_t.data>
attribute allows you to store some information along with your L<UV::Handle>
object. Since libuv does not make use of this attribute in any way, you're free
to use it for your own purposes.

=head2 loop

    # read-only attribute
    my $loop = $handle->loop();

The L<loop|http://docs.libuv.org/en/v1.x/handle.html#c.uv_handle_t.loop>
attribute is a B<read-only> attribute that returns the L<UV::Loop> object this
handle was initialized with.

=head2 type

    # read-only attribute
    my $int = $handle->type();
    if ($int == UV::Handle::UV_TIMER) {
        say "This handle is a timer";
    }

The L<type|http://docs.libuv.org/en/v1.x/handle.html#c.uv_handle_t.type>
attribute is a B<read-only> attribute that returns the corresponding libuv
handle type constant.

=head1 METHODS

L<UV::Handle> makes the following methods available.

=head2 active

    my $int = $handle->active();

The L<active|http://docs.libuv.org/en/v1.x/handle.html#c.uv_is_active> method
returns non-zero if the handle is active, zero if it's inactive. What "active"
means depends on the type of handle:

=over 4

=item

A L<UV::Async> handle is always active and cannot be deactivated, except by
closing it with C<< $handle->close() >>.

=item

A L<UV::Pipe>, L<UV::TCP>, L<UV::UDP>, etc. handle - basically any handle
that deals with i/o - is active when it is doing something that involves
i/o, like reading, writing, connecting, accepting new connections, etc.

=item

A L<UV::Check>, L<UV::Idle>, L<UV::Timer>, etc. handle is active when it
has been started with a call to C<< $handle->start() >>, etc.

=back

B<* Rule of thumb:> if a handle of type C<foo> has a C<< $foo->start() >>
function, then it's active from the moment that function is called. Likewise,
C<< $foo->stop() >> deactivates the handle again.

=head2 close

    $handle->close();
    $handle->close(sub {say "we're closing"});

The L<close|http://docs.libuv.org/en/v1.x/handle.html#c.uv_close> method
requests that the handle be closed. The C<close> event will be fired
asynchronously after this call. This B<MUST> be called on each handle before
memory is released.

Handles that wrap file descriptors are closed immediately but the C<close>
event will still be deferred to the next iteration of the event loop. It gives
you a chance to free up any resources associated with the handle.

In-progress requests, like C<< $handle->connect() >> or C<< $handle->write >>,
are canceled and have their callbacks called asynchronously with
C<< status = UV::UV_ECANCELED >>.

=head2 closing

    my $int = $handle->closing();

The L<closing|http://docs.libuv.org/en/v1.x/handle.html#c.uv_is_closing>
method returns non-zero if the handle is closing or closed, zero otherwise.

B<* Note:> This function should only be used between the initialization of the
handle and the arrival of the C<close> callback.

=head2 has_ref

    my $int = $handle->has_ref();

The L<has_ref|http://docs.libuv.org/en/v1.x/handle.html#c.uv_has_ref>
method returns non-zero if the handle is referenced, zero otherwise.

See L<Reference Counting|http://docs.libuv.org/en/v1.x/handle.html#refcount>.

=head2 is_active

    # simply a synonym for ->active()
    my $int = $handle->is_active();

A synonym for L<UV::Handle/"active">.

=head2 is_closing

    # simply a synonym for ->closing()
    my $int = $handle->is_closing();

A synonym for L<UV::Handle/"closing">.

=head2 on

    # set a close event callback to print the handle's data attribute
    $handle->on('close', sub {
        my $hndl = shift;
        say $hndl->data();
        say "closing!"
    });

    # clear out the close event callback for the handle
    $handle->on(close => undef);
    $handle->on(close => sub {});

The C<on> method allows you to subscribe to L<UV::Handle/"EVENTS"> emitted by
any UV::Handle or subclass.

=head2 ref

    $handle->ref();

The L<ref|http://docs.libuv.org/en/v1.x/handle.html#c.uv_ref>
method references the given handle. References are idempotent, that is, if a
handle is already referenced, then calling this function again will have no
effect.

See L<Reference Counting|http://docs.libuv.org/en/v1.x/handle.html#refcount>.

=head2 unref

    $handle->unref();

The L<unref|http://docs.libuv.org/en/v1.x/handle.html#c.uv_unref>
method un-references the given handle. References are idempotent, that is, if a
handle is not referenced, then calling this function again will have no
effect.

See L<Reference Counting|http://docs.libuv.org/en/v1.x/handle.html#refcount>.


=head1 AUTHOR

Chase Whitener <F<capoeirab@cpan.org>>

=head1 AUTHOR EMERITUS

Daisuke Murase <F<typester@cpan.org>>

=head1 COPYRIGHT AND LICENSE

Copyright 2012, Daisuke Murase.

This library is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.

=cut
