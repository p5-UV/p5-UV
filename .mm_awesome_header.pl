use Config;
use Alien::libuv ();

# make sure we actually get stuff back from Alien::libuv
sub TRIM {
    my $s = shift;
    return '' unless $s;
    $s =~ s/\A\s*//;
    $s =~ s/\s*\z//;
    return $s;
}


my @flags = ('-I.', '-I../..', $Config{ccflags});
push @flags, '-DDEBUG' if $ENV{PERL_UV_DEBUG};
my $libs = Alien::libuv->libs();
{
    my $cflags = TRIM(Alien::libuv->cflags);
    my $cflags_s = TRIM(Alien::libuv->cflags_static);
    if ($cflags eq $cflags_s) {
        unshift @flags, $cflags if $cflags;
    }
    else {
        unshift @flags, $cflags if $cflags;
        unshift @flags, $cflags_s if $cflags_s;
    }
}
my %xsbuild = (
    XSMULTI => 1,
    XSBUILD => {
        xs => {
            'lib/UV' => {
              OBJECT => 'lib/UV$(OBJ_EXT) lib/perl_math_int64$(OBJ_EXT)',
            },
        },
    },
    OBJECT  => '$(O_FILES)',
    LIBS => [$libs],
    CCFLAGS => join(' ', @flags),
);
