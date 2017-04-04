#! perl

use strict;
use warnings;

use Test2::Bundle::Extended;

use Data::Edit::Struct qw[ edit ];

use Scalar::Util qw[ refaddr ];

isa_ok(
    dies {
        edit(
            replace => {
                dest  => [ 0, 10, 20, 40 ],
                dpath => '/*[0]',
                src => [ [ 1, 2, 3, 4 ], [ 5, 6, 7, 8 ] ],
                spath => '/*/*[0]',
            },
          )
    },
    ['Data::Edit::Struct::failure::input::src'],
    'multiple sources not accepted in default mode'
);

subtest 'hash' => sub {

    my %defaults = ( multimode => 'hash' );

    isa_ok(
        dies {
            edit(
                replace => {
                    %defaults,
                    dest  => [ 0, 10, 20, 40 ],
                    dpath => '/*[0]',
                    src => [ [ 1, 2, 3, 4 ], [ 5, 6, 7, 8 ] ],
                    spath => '/',
                },
              )
        },
        ['Data::Edit::Struct::failure::input::src'],
        "can't convert root to hash"
    );

    {
        my @dest = ( 0, 10, 20, 40 );
        edit(
            replace => {
                %defaults,
                dest  => \@dest,
                dpath => '/*[0]',
                src   => { foo => [1], bar => [5], baz => [5] },
                spath => '/*/*[value == 5 || value == 1]/..',
            },
        );

        is( \@dest, [ { foo => [1], bar => [5], baz => [5] }, 10, 20, 40 ],
            "replace" );
    }

    {
        my @dest = ( 0, 10, 20, 40 );

        edit(
            insert => {
                %defaults,
                dest  => \@dest,
                dpath => '/*[1]',
                src   => { foo => 1, bar => 5, baz => 3 },
                spath => '/*[value == 5]',
                stype => 'container',
            },
        );

        is( \@dest, [ 0, bar => 5, 10, 20, 40 ], "insert" );
    }

    {
        my @dest = ( 0, 10, 20, 40 );

        edit(
            splice => {
                %defaults,
                dest  => \@dest,
                dpath => '/*[1]',
                src   => { foo => 1, bar => 5, baz => 3 },
                spath => '/*[value < 5]',
                stype => 'element',
            },
        );

        is( \@dest, [ 0, { foo => 1, baz => 3 }, 20, 40 ], "splice" );
    }

};

subtest 'array' => sub {

    my %defaults = ( multimode => 'array' );

    {
        my @dest = ( 0, 10, 20, 40 );
        edit(
            replace => {
                %defaults,
                dest  => \@dest,
                dpath => '/*[0]',
                src   => [ 1, 2, 3, 4 ],
                spath => '/*',
            },
        );

        is( \@dest, [ [ 1, 2, 3, 4 ], 10, 20, 40 ],
            "replace" );
    }

    {
        my @dest = ( 0, 10, 20, 40 );
        edit(
            insert => {
                %defaults,
                dest  => \@dest,
                dpath => '/*[0]',
                src   => [ 1, 2, 3, 4 ],
                spath => '/*',
		stype => 'element',
            },
        );

        is( \@dest, [ [ 1, 2, 3, 4 ], 0, 10, 20, 40 ],
            "insert" );
    }


    {
        my @dest = ( 0, 10, 20, 40 );

        edit(
            splice => {
                %defaults,
                dest  => \@dest,
                dpath => '/*[1]',
                src   => [ 1, 2, 3, 4 ],
                spath => '/*',
                stype => 'element',
            },
        );

        is( \@dest, [ 0, [ 1, 2, 3, 4 ], 20, 40 ], "splice" );
    }
};

subtest 'iterate' => sub {
    isa_ok(
        dies {
            edit(
                replace => {
                    dest  => [ 0, 10, 20, 40 ],
                    dpath => '/*[0]',
                    src => [ [ 1, 2, 3, 4 ], [ 5, 6, 7, 8 ] ],
                    spath     => '/*/*[0]',
                    multimode => 'iterate',
                },
              )
        },
        ['Data::Edit::Struct::failure::input::src'],
        'multiple sources not accepted for replace operation'
    );
};

done_testing;
