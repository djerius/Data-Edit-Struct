#! perl

use Test2::Bundle::Extended;
use Test2::API qw[ context ];

use experimental qw[ postderef switch signatures ];

use Data::Edit::Struct qw[ edit ];

subtest 'container' => sub {

    my %defaults = ( use_dest_as => 'container' );

    subtest 'dest => array' => sub {

        test_insert( %defaults, %$_ )
          for ( {
                dest  => [ 10, 20, 30, 40 ],
                dpath => '/',
                src    => [ 1, 2 ],
                offset => 0,
                expected => [ 1, 2, 10, 20, 30, 40 ],
            },
            {
                dest  => [ 10, 20, 30, 40 ],
                dpath => '/',
                src    => [ 21, 22 ],
                offset => 2,
                expected => [ 10, 20, 21, 22, 30, 40 ],
            },
            {
                dest  => [ 10, 20, 30, 40 ],
                dpath => '/',
                src    => [ 41, 42 ],
                offset => -1,
                expected => [ 10, 20, 30, 40, 41, 42 ],
            },
            {
                dest  => [ 10, 20, 30, 40 ],
                dpath => '/',
                src    => [ 31, 32 ],
                offset => 3,
                expected => [ 10, 20, 30, 31, 32, 40 ],
            },
            {
                dest  => [ 10, 20, 30, 40 ],
                dpath => '/',
                src    => [ 41, 42 ],
                offset => 4,
                expected => [ 10, 20, 30, 40, 41, 42 ],
            },
            {
                dest  => [ 10, 20, 30, 40 ],
                dpath => '/',
                src    => { 41 => 42 },
                offset => 4,
                expected => [ 10, 20, 30, 40, 41, 42 ],
            },

          );

    };

    subtest 'dest => hash' => sub {

        test_insert( %defaults, %$_ )
          for ( {
                dest  => { foo => 1, bar => 2 },
                dpath => '/',
                src      => [ baz => 3 ],
                expected => { foo => 1, bar => 2, baz => 3 },
            },
            {
                dest  => { foo => 1, bar => 2 },
                dpath => '/',
                src      => { baz => 3 },
                expected => { foo => 1, bar => 2, baz => 3 },
            },
          );

    };

    subtest 'errors' => sub {

        my %defaults = (
            %defaults,
            dest  => { foo => 1 },
            dpath => '/foo',
            src => [ 0, 1 ],
        );

        isa_ok(
            dies { edit( splice => \%defaults ) },
            ['Data::Edit::Struct::failure::input::dest'],
            'destination must be an array or hash',
        );

    };


};

subtest 'element' => sub {

    my %defaults = ( use_dest_as => 'element' );

    subtest 'dest => array' => sub {

        test_insert( %defaults, %$_ )
          for ( {
                dest  => [ 10, 20, 30, 40 ],
                dpath => '/*[0]',
                src    => [ 1, 2 ],
                offset => 0,
                expected => [ 1, 2, 10, 20, 30, 40 ],
            },
            {
                dest  => [ 10, 20, 30, 40 ],
                dpath => '/*[1]',
                src    => [ 21, 22 ],
                offset => 1,
                expected => [ 10, 20, 21, 22, 30, 40 ],
            },
            {
                dest  => [ 10, 20, 30, 40 ],
                dpath => '/*[2]',
                src    => [ 41, 42 ],
                offset => -1,
                expected => [ 10, 20, 30, 40, 41, 42 ],
            },
            {
                dest  => [ 10, 20, 30, 40 ],
                dpath => '/*[2]',
                src    => [ 31, 32 ],
                offset => 1,
                expected => [ 10, 20, 30, 31, 32, 40 ],
            },
            {
                dest  => [ 10, 20, 30, 40 ],
                dpath => '/*[2]',
                src    => [ 41, 42 ],
                offset => 2,
                expected => [ 10, 20, 30, 40, 41, 42 ],
            },
            {
                dest  => [ 10, 20, 30, 40 ],
                dpath => '/*[3]',
                src    => { 41 => 42 },
                offset => 1,
                expected => [ 10, 20, 30, 40, 41, 42 ],
            },

          );

    };


    subtest 'errors' => sub {

        my @params = ( {
            dest  => { foo => 1 },
            dpath => '/foo',
            src => [ 0, 1 ],
          },
          {
            dest  => [ 10, 20 ],
            dpath => '/',
            src   => [ 0,  1 ],
          } );

        for ( @params ) {

            my %arg = ( %defaults, %$_ );
            isa_ok(
                dies { edit( insert => \%arg ) },
                ['Data::Edit::Struct::failure::input::dest'],
                _make_label( \%arg ) . ':destination must be an array or hash'
            );
        }
    };
};

subtest auto => sub {

    my %defaults = ( use_dest_as => 'auto' );

    subtest 'container' => sub {

        test_insert( %defaults, %$_ )
          for ( {
                dest  => [ 10, 20, 30, 40 ],
                dpath => '/',
                src    => [ 1, 2 ],
                offset => 0,
                expected => [ 1, 2, 10, 20, 30, 40 ],
            } );
    };

    subtest 'element' => sub {

        test_insert( %defaults, %$_ )
          for ( {
		 dest  => [ 10, 20, 30, 40 ],
		 dpath => '/*[0]',
		 src    => [ 1, 2 ],
		 offset => 0,
		 expected => [ 1, 2, 10, 20, 30, 40 ],
		},
	   )
      };

};

sub test_insert( %arg ) {

    my $ctx = context();

    my $expected = delete $arg{expected};


    my $label = _make_label( \%arg );


    edit( insert => \%arg );

    my $ok = is( $arg{dest}, $expected, "$label" );
    $ctx->release;
    return $ok;
}

sub _make_label( $arg ) {

    my $label
      = Data::Dumper->new( [$arg], ['Args'] )->Indent( 0 )->Quotekeys( 0 )
      ->Sortkeys( 1 )->Dump;

    $label =~ s/\$Args\s*=\s*\{//;
    $label =~ s/};//;

    return $label;
}

done_testing;
