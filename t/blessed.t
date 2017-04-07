#! perl

use strict;
use warnings;

use Test2::Bundle::Extended;

use Data::Edit::Struct qw[ edit ];


my $src = bless { a => 1, b => 2 }, 'Foo';


{
    my $dest = [];

    edit(
        insert => {
            dest  => $dest,
            dpath => '/',
            src   => $src,
            stype => 'auto'
        },
    );

    is ( $dest->[0], $src, "object auto treated as element" );
}

done_testing;
