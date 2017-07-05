on 'runtime' => sub {
    requires 'perl' => '5.008001';
    requires 'strict';
    requires 'warnings';
    requires 'Alien::libuv' => '0.004';
    requires 'Exporter' => '5.57';
    requires 'XSLoader' => '0.14';
};

on 'build' => sub {
    requires 'Alien::libuv' => '0.004';
    requires 'Config';
    requires 'ExtUtils::MakeMaker' => '7.12';
};

on 'configure' => sub {
    requires 'Alien::libuv' => '0.004';
};

on 'test' => sub {
    requires 'Test::More' => '0.88';
};

on 'develop' => sub {
    requires 'Pod::Coverage::TrustPod';
    requires 'Test::CheckManifest' => '1.29';
    requires 'Test::CPAN::Changes' => '0.4';
    requires 'Test::CPAN::Meta';
    requires 'Test::Kwalitee'      => '1.22';
    requires 'Test::Pod::Coverage';
    requires 'Test::Pod::Spelling::CommonMistakes' => '1.000';
};
