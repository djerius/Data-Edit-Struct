#! perl

use strict;
use warnings;

use Test2::Bundle::Extended;

use Data::Edit::Struct qw[ edit ];



subtest 'hash src' => sub {
    my $dest = [];
    my $src = { a => 1 };

    edit(
        insert => {
            dest  => $dest,
            dpath => '/',
            src   => $src,
            stype => 'auto'
        },
    );

    is ( $dest, [ %$src ], "unblessed" );

    $dest = [];
    bless $src;

    edit(
        insert => {
            dest  => $dest,
            dpath => '/',
            src   => $src,
            stype => 'auto'
        },
    );


    is ( $dest->[0], $src, "blessed" );
};

subtest "array src" => sub {

    my $dest = [];
    my $src = [ a => 1 ];

    edit(
        insert => {
            dest  => $dest,
            dpath => '/',
            src   => $src,
            stype => 'auto'
        },
    );

    is ( $dest, [ @$src ], "unblessed" );

    $dest = [];
    bless $src;

    edit(
        insert => {
            dest  => $dest,
            dpath => '/',
            src   => $src,
            stype => 'auto'
        },
    );


    is ( $dest->[0], $src, "blessed" );
};



done_testing;
