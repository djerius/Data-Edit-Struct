#! perl

use strict;
use warnings;

use Test2::Bundle::Extended;

use Data::Edit::Struct qw[ edit ];


subtest 'src' => sub {

    my $dest;
    my $src;

    my $edit = sub {
        edit(
            insert => {
                dest  => $dest,
                dpath => '/',
                src   => $src,
                stype => 'auto'
            },
        );
        return $dest;
    };

    subtest 'hash' => sub {
        $dest = [];
        $src = { a => 1 };

        is( $edit->(), [%$src], "unblessed" );

        $dest = [];
        bless $src;

        is( $edit->()->[0], $src, "blessed" );
    };

    subtest "array" => sub {

        $dest = [];
        $src = [ a => 1 ];

        is( $edit->(), [@$src], "unblessed" );

        $dest = [];
        bless $src;

        is( $edit->()->[0], $src, "blessed" );
    };

};


done_testing;
