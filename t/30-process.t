use strict;
use warnings;

use UV::Loop ();
use UV::Process ();

use Test::More;

use POSIX ();

my $exit_cb_called = 0;

sub exit_cb {
    my $self = shift;
    $exit_cb_called++;
}

my $process = UV::Process->spawn(
    file => $^X,
    args => [qw( -e 1 )],
    on_exit => \&exit_cb,
);
isa_ok($process, 'UV::Process');

is(UV::Loop->default()->run(), 0, 'Default loop ran');

is($exit_cb_called, 1, "The exit callback was run");

{
    my $exit_status;

    my $process = UV::Process->spawn(
        file => $^X,
        args => [ "-e", "exit 5" ],
        on_exit => sub {
            (undef, $exit_status, undef) = @_;
        },
    );

    UV::Loop->default()->run();

    is($exit_status, 5, 'exit status from `perl -e "exit 5"`');
}

{
    my $term_signal;

    my $process = UV::Process->spawn(
        file => $^X,
        args => [ "-e", 'kill SIGTERM => $$' ],
        on_exit => sub {
            (undef, undef, $term_signal) = @_;
        },
    );

    UV::Loop->default()->run();

    is($term_signal, POSIX::SIGTERM, 'term signal from `perl -e "kill SIGTERM => $$"`');
}

{
    my $exit_status;

    my $process = UV::Process->spawn(
        file => $^X,
        args => [ "-e", 'exit ($ENV{VAR} eq "value")' ],
        env => {
            VAR => "value",
        },
        on_exit => sub {
            (undef, $exit_status, undef) = @_;
        },
    );
    UV::Loop->default()->run();
    is($exit_status, 1, 'exit status from process with env');
}

done_testing();
