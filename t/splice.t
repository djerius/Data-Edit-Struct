#! perl

use Test2::Bundle::Extended;
use Test2::API qw[ context ];

use experimental qw[ postderef switch signatures ];

use Data::Edit::Struct qw[ edit ];

subtest 'container' => sub {

    my %defaults = ( use_dest_as => 'container' );

    subtest 'no replacement (e.g. deletion)' => sub {

        cmp_splice( %defaults, %$_ )
          for ( {
                input => [ 10, 20, 30, 40 ],
            },

            {
                input  => [ 10, 20, 30, 40 ],
                offset => 1,
            },
            {
                input  => [ 10, 20, 30, 40 ],
                offset => 1,
                length => 2,
            },
          );

    };

    subtest 'replacement' => sub {

        cmp_splice( %defaults, %$_ )
          for ( {
                input => [ 10, 20, 30, 40 ],
                src   => [ 50, 60 ],
            },

            {
                input  => [ 10, 20, 30, 40 ],
                offset => 1,
                src => [ 50, 60 ],
            },
            {
                input  => [ 10, 20, 30, 40 ],
                offset => 1,
                length => 2,
                src => [ 50, 60 ],
            },
          );

    };

    subtest errors => sub {

        my %defaults = ( %defaults, dest => { foo => 1 }, dpath => '/' );

        isa_ok(
            dies { edit( splice => { %defaults, dpath => '/' } ) },
            ['Data::Edit::Struct::failure::input::dest'],
            'destination container must be an array'
        );

    };


};


subtest 'element' => sub {

    my %defaults = (
        use_dest_as => 'element',
        dpath       => '/*[%d]',
        idx         => 1,
    );

    subtest 'no replacement (e.g. deletion)' => sub {

        cmp_splice( %defaults, %$_ )
          for ( {
                input => [ 10, 20, 30, 40 ],
            },

            {
                input  => [ 10, 20, 30, 40 ],
                offset => 1,
            },
            {
                input  => [ 10, 20, 30, 40 ],
                offset => 1,
                length => 2,
            },
          );

    };

    subtest 'replacement' => sub {

        cmp_splice( %defaults, %$_ )
          for ( {
                input => [ 10, 20, 30, 40 ],
                src   => [ 50, 60 ],
            },

            {
                input  => [ 10, 20, 30, 40 ],
                offset => 1,
                src => [ 50, 60 ],
            },
            {
                input  => [ 10, 20, 30, 40 ],
                offset => 1,
                length => 2,
                src => [ 50, 60 ],
            },
          );

    };

    subtest errors => sub {

        my %defaults = ( %defaults, dest => { foo => 1 } );
        delete $defaults{idx};

        isa_ok(
            dies { edit( splice => { %defaults, dpath => '/' } ) },
            ['Data::Edit::Struct::failure::input::dest'],
            'destination element requires parent',
        );

        isa_ok(
            dies { edit( splice => { %defaults, dpath => '/foo' } ) },
            ['Data::Edit::Struct::failure::input::dest'],
            'destination parent must be array',
        );

    };

};

subtest 'auto' => sub {

    my %defaults = ( use_dest_as => 'auto' );

    subtest 'element' => sub {

        my %defaults = (
            %defaults,
            dpath => '/*[%d]',
            idx   => 1,
        );

        subtest 'no replacement (e.g. deletion)' => sub {

            cmp_splice( %defaults, %$_ )
              for ( {
                    input  => [ 10, 20, 30, 40 ],
                    offset => 1,
                    length => 2,
                },
              );

        };

        subtest 'replacement' => sub {

            cmp_splice( %defaults, %$_ )
              for ( {
                    input  => [ 10, 20, 30, 40 ],
                    offset => 1,
                    length => 2,
                    src => [ 50, 60 ],
                },
              );

        };

    };

    subtest "container" => sub {

        subtest 'no replacement (e.g. deletion)' => sub {

            cmp_splice( %defaults, %$_ )
              for ( {
                    input  => [ 10, 20, 30, 40 ],
                    offset => 1,
                    length => 2,
                },
              );

        };

        subtest 'replacement' => sub {

            cmp_splice( %defaults, %$_ )

              for ( {
                    input  => [ 10, 20, 30, 40 ],
                    offset => 1,
                    length => 2,
                    src => [ 50, 60 ],
                },
              );
        };
    };

    subtest errors => sub {

        my %defaults = ( %defaults, dest => { foo => 1 } );

        isa_ok(
            dies { edit( splice => \%defaults ) },
            ['Data::Edit::Struct::failure::input::dest'],
            'destination must be an array or array element',
        );

    };

};


sub cmp_splice( %arg ) {

    my $ctx = context();

    if ( defined $arg{dpath} && $arg{dpath} =~ /%/ ) {
        $arg{dpath}
          = sprintf( $arg{dpath}, ( defined $arg{idx} ? $arg{idx} : () ) );
    }


    my $label
      = Data::Dumper->new( [ \%arg ], ['Args'] )->Indent( 0 )->Quotekeys( 0 )
      ->Sortkeys( 1 )->Dump;

    $label =~ s/\$Args\s*=\s*\{//;
    $label =~ s/};//;

    my $input = delete $arg{input};
    my $idx   = delete $arg{idx};


    my @input = $input->@*;
    splice(
        @input,
        ( $idx // 0 ) + ( $arg{offset} // 0 ),
        $arg{length} // 1,
        ( defined $arg{src} ? $arg{src}->@* : () ),
    );

    my $dest = [ $input->@* ];
    edit(
        splice => {
            %arg, dest => $dest,
        },
    );

    my $ok = is( $dest, \@input, "$label" );
    $ctx->release;
    return $ok;
}

done_testing;
