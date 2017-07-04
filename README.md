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

# COPYRIGHT AND LICENSE

Copyright 2017, Chase Whitener.

This library is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.
