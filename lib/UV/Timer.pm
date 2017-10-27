package UV::Timer;

our $VERSION = '1.000004';
$VERSION = eval $VERSION;

use strict;
use warnings;

use parent 'UV::Handle';

1;

__END__

=encoding utf8

=head1 NAME

UV::Timer - Timers in libuv

=head1 SYNOPSIS

  #!/usr/bin/env perl
  use strict;
  use warnings;

  use UV;

  # A new handle will be initialized against the default loop
  my $timer = UV::Timer->new();

  # Use a different loop
  my $loop = UV::Loop->new(); # non-default loop
  my $timer = UV::Timer->new($loop);

  # setup the timer callback:
  $timer->on("timer", sub {say "We're TIMING!!!"});

  # start the timer
  $timer->start(); # same as ->start(0, 0);
  $timer->start(1, 0);
  $timer->start(1, 0, sub {say "override any TIMER callback we already have"});

  # stop the timer
  $timer->stop();

=head1 DESCRIPTION

This module provides an interface to
L<libuv's timer|http://docs.libuv.org/en/v1.x/timer.html>. We will try to
document things here as best as we can, but we also suggest you look at the
L<libuv docs|http://docs.libuv.org> directly for more details on how things
work.

=head1 EVENTS

L<UV::Timer> inherits all events from L<UV::Handle> and also makes the
following extra events available.

=head2 timer

    $timer->on("timer", sub { my $invocant = shift; say "We are timing!"});
    my $count = 0;
    $timer->on("timer", sub {
        my $invocant = shift; # the timer instance this event fired on
        if (++$count > 2) {
            say "We've timed twice. stopping!";
            $invocant->stop();
        }
    });

When the event loop runs and the timer is ready, this event will be fired.

=head1 METHODS

L<UV::Timer> inherits all methods from L<UV::Handle> and also makes the
following extra methods available.

=head2 new

    my $timer = UV::Timer->new();
    # Or tell it what loop to initialize against
    my $timer = UV::Timer->new($loop);

This constructor method creates a new L<UV::Timer> object and
L<initializes|http://docs.libuv.org/en/v1.x/timer.html#c.uv_timer_init> the
timer with the given L<UV::Loop>. If no L<UV::Loop> is provided, then the
L<UV::Loop/"default_loop"> is assumed.

=head2 again

    my $int = $timer->again();

The L<again|http://docs.libuv.org/en/v1.x/timer.html#c.uv_timer_again> method
stops the timer, and if it is repeating, restarts it using the repeat value as
the timeout.  If the timer has never been started, it returns C<UV::UV_EINVAL>.

=head2 get_repeat

    my $uint64_t = $timer->get_repeat();

The L<get_repeat|http://docs.libuv.org/en/v1.x/timer.html#c.uv_timer_get_repeat>
method returns the timer's repeat value.

=head2 set_repeat

    $timer->set_repeat(12345);

The L<set repeat|http://docs.libuv.org/en/v1.x/timer.html#c.uv_timer_set_repeat>
method sets the repeat interval in I<milliseconds>. The timer will be scheduled
to run on the given interval, regardless of the callback execution duration,
and will follow normal timer semantics in the case of a time-slice overrun.

For example, if a 50ms repeating timer first runs for 17ms, it will be scheduled
to run again 33ms later. If other tasks consume more than the 33ms following
the first timer callback, then the callback will run as soon as possible.

B<* Note:> If the repeat value is set from a timer callback it does not
immediately take effect. If the timer was non-repeating before, it will have
been stopped. If it was repeating, then the old repeat value will have been
used to schedule the next timeout.

=head2 start

    # assume no timeout or repeat values
    $timer->start();

    # explicitly state timeout and repeat values
    my $timeout = 0;
    my $repeat = 0;
    $timer->start($timeout, $repeat);

    # pass a callback for the "timer" event
    $timer->start(0, 0, sub {say "yay"});
    # providing the callback above completely overrides any callback previously
    # set in the ->on() method. It's equivalent to:
    $timer->on(timer => sub {say "yay"});
    $timer->start(0, 0);

The L<start|http://docs.libuv.org/en/v1.x/timer.html#c.uv_timer_start> method
starts the timer. The C<timeout> and C<repeat> values are in milliseconds.

If C<timeout> is zero, the callback fires on the next event loop iteration. If
C<repeat> is non-zero, the callback fires first after timeout milliseconds and
then repeatedly after C<repeat> milliseconds.

B<* Note:> Does not update the event loop's concept of L<UV::Loop/"now">. See
L<UV::Loop/"update_time"> for more information.

=head2 stop

    $timer->stop();

The L<stop|http://docs.libuv.org/en/v1.x/timer.html#c.uv_timer_stop> method
stops the timer, and if it is repeating, restarts it using the repeat value
as the timeout. If the timer has never been started before it returns
C<UV_EINVAL>.

=head1 AUTHOR

Chase Whitener <F<capoeirab@cpan.org>>

=head1 AUTHOR EMERITUS

Daisuke Murase <F<typester@cpan.org>>

=head1 COPYRIGHT AND LICENSE

Copyright 2012, Daisuke Murase.

This library is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.

=cut
