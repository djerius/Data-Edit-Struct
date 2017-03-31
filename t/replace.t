#! perl

use strict;
use warnings;

use Test2::Bundle::Extended;

use Data::Edit::Struct qw[ edit ];

use Scalar::Util qw[ refaddr ];

$Data::DPath::USE_SAFE = 0;
subtest 'hash value' => sub {
    my %dest = ( array => [ 0, 10, 20, 40 ], );

    edit(
        replace => {
            dest  => \%dest,
            dpath => '/array',
            src   => ['foo'],
        },
    );

    use DDP;

    is( \%dest, { array => ['foo'] }, "replaced" );

};

subtest 'hash key' => sub {

    subtest 'string key' => sub {
        my %dest = ( array => [ 0, 10, 20, 40 ], );
        my $aref = $dest{array};

        edit(
            replace => {
                dest    => \%dest,
                dpath   => '/array',
                replace => 'key',
                src     => 'foo',
            },
        );

        is( \%dest, { foo => $aref }, "key replaced" );
        is( refaddr( $dest{foo} ), refaddr( $aref ), "contents retained" );
    };

    subtest 'reference key' => sub {
        my %dest = ( array => [ 0, 10, 20, 40 ], );
        my $aref = $dest{array};
        my $raref = refaddr( $aref );
        edit(
            replace => {
                dest    => \%dest,
                dpath   => '/array',
                replace => 'key',
                src     => $aref,
            },
        );

        is( \%dest, { $raref => $aref }, "key replaced" );
        is( refaddr( $dest{$raref} ), $raref, "contents retained" );
    };


};

done_testing;
