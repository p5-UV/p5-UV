use Alien::Base::Wrapper ();

my %xsbuild = Alien::Base::Wrapper->new('Alien::libuv')->mm_args2(
    XSMULTI => 1,
    XSBUILD => {
        xs => {
            'lib/UV' => {
              OBJECT => 'lib/UV$(OBJ_EXT) lib/perl_math_int64$(OBJ_EXT) lib/p5uv_constants$(OBJ_EXT)',
            },
        },
    },
    OBJECT  => '$(O_FILES)',
);
# Our cpanfile contains the proper configure requires already
delete $xsbuild{CONFIGURE_REQUIRES};
