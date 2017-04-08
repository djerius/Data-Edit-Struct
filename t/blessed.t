#! perl

use strict;
use warnings;

use Test2::Bundle::Extended;

use Data::Edit::Struct qw[ edit ];



{
    my $dest = [];
    my $src = bless { a => 1, b => 2 }, 'Foo';

    edit(
        insert => {
            dest  => $dest,
            dpath => '/',
            src   => $src,
            stype => 'auto'
        },
    );

    is ( $dest->[0], $src, "blessed hash src" );
}

{
    my $dest = [];
    my $src = bless [ 1, 2, 3 ], 'Foo';

    edit(
        insert => {
            dest  => $dest,
            dpath => '/',
            src   => $src,
            stype => 'auto'
        },
    );

    is ( $dest->[0], $src, "blessed array src" );
}

done_testing;
