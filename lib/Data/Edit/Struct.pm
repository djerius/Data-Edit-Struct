package Data::Edit::Struct;

# ABSTRACT: Edit a Perl structure addressed with a Data::DPath path

use strict;
use warnings;
use experimental qw[ postderef switch signatures ];

use Exporter 'import';

our $VERSION = '0.01';

use Ref::Util qw[ is_arrayref is_hashref is_scalarref is_ref ];

use Data::Edit::Struct::Types -all;

use PerlX::Assert;
use List::Util qw[ pairmap ];
use Scalar::Util qw[ refaddr ];
use Params::ValidationCompiler qw[ validation_for ];
use Types::Standard -types;

use Data::DPath qw[ dpath ];

use Carp;

our @EXPORT_OK = qw[ edit ];

my %dest = (
    dest  => { type => Context },
    dpath => { type => Str, default => '/' },
);

my %use_dest_as
  = ( use_dest_as => { type => Enum [ 'idx', 'container' ], default => 'auto' } );

my %source = (
    source        => { type => Context,     optional => 1 },
    spath         => { type => Str,         default  => '/' },
    use_source_as => { type => UseSourceAs, default  => 'auto' },
);

my %length = ( length => { type => Int, default => 1 } );
my %offset = ( offset => { type => IntArray, default => sub { [0] } } );

my %multimode = ( multimode => { type => Enum [ 'iterate', 'array', 'hash', 'error' ], default => 'error'  } );

my %Validation = (
    pop    => { %dest, %length },
    shift  => { %dest, %length },
    splice => { %dest, %length, %offset, %source, %use_dest_as, %multimode },
    insert => { %dest, %length, %offset, %source, %use_dest_as, %multimode  },
    delete => {
        %dest,
        use_dest_as => {
            type => Enum [ 'value', 'key' ],
            default => 'value',
        },
    },
);

my %Validator = map { $_ => validation_for(
    params => $Validation{$_},
    name   => $_,
  ) }
  keys %Validation;

sub dup_context ( $context ) {
    Data::DPath::Context->new->current_points( $context->current_points );
}


sub edit ( $action, %request ) {

    croak( "no action specified\n" ) unless defined $action;
    my $validator = $Validator{$action} // croak( "unknown acton: $action\n" );

    my %arg = $validator->( %request );

    my $src;

    if ( exists $arg{src} ) {


        for ( $arg{multimode} ) {

            when ( 'array' ) {
                $src = [ [ dup_context( $arg{src} )->matchr( $arg{spath} ) ] ];
            }

            when ( 'hash' ) {

                my %src;

                for my $point ( dup_context( $arg{src} )->_search( $arg{spath} )
                    ->current_points )
                {

                    my $attr = $point->attr;
                    my $key = $attr->{key} // $attr->{idx}
                      or croak(
                        "source path returned multiple values; unable to convert into hash as element has no `key' or `idx' attribute\n"
                      );
                    $src{$key} = $point->deref->$*;
                }

                $src = [ \%src ];
            }

            when ( 'iterate' ) {
                $src = [ dup_context( $arg{src} )->matchr( $arg{spath} ) ];
            }

            default {

                my @src = dup_context( $arg{src} )->matchr( $arg{spath} );

                croak( "source path may not have multiple resolutions\n" )
                  if @src > 1;

                $src = [ $src[0] ];

            }

        }

    }

    my $points
      = dup_context( $arg{dest} )->_search( dpath($arg{dpath}) )->current_points;


    for ( $action ) {

        when ( 'pop' ) {

            for my $point ( @$points ) {

                my $dest = $point->ref->$*;
                croak( "pop destination is not an array\n" )
                  unless is_arrayref( $dest );

                my $length = $arg{length};
                $length = @$dest if $length > @$dest;
                splice( @$dest, -$length, $length );
            }

        }

        when ( 'shift' ) {

            for my $point ( @$points ) {
                my $dest = $point->ref->$*;
                croak( "pop destination is not an array\n" )
                  unless is_arrayref( $dest );
                splice( @$dest, 0, $arg{length} );
            }

        }

        when ( 'splice' ) {

            _splice( $arg{use_dest_as}, $points, $arg{offset}, $arg{length}, $_ )
	      foreach @$src;
        }

        when ( 'insert' ) {
            _insert( $arg{use_dest_as}, $points, $arg{offset}, $arg{length}, $_ )
	      foreach @$src;
        }


        when ( 'delete' ) {
            _delete( $points );
        }

        when ( 'replace' ) {
            _replace( $points, $arg{use_dest_as}, $arg{src} ),
	      foreach @$src;
        }
    }

}


sub _deref ( $use_source_as, $value ) {

    my $use = $use_source_as;
    $use = is_ref( $value ) ? 'container' : 'value'
      if $use eq 'auto';

    for ( $use ) {

        when ( 'value' ) {

            return [$value];
        }

        when ( 'container' ) {

            return
                is_arrayref( $value )  ? $value
              : is_hashref( $value )   ? [%$value]
              : is_scalarref( $value ) ? [$$value]
	      : croak( "\$value is not an array, hash, or scalar reference\n" );
        }

        default {

            croak( "unknown mode to use source in: $_\n" );
        }

    }
}

sub _splice ( $use_dest_as, $points, $offset, $length, $replace ) {

    for my $point ( @$points )  {

        my $ref;

        my $idx = $point->attrs->{idx};

        my $use = $use_dest_as;

        if ( $use_dest_as eq 'auto' ) {

            $ref = $point->ref;
            $use
              = is_arrayref( $ref ) ? 'container'
              : defined $idx        ? 'idx'
              :   croak( "point is neither an array element nor an array ref\n" );
        }

        for ( $use ) {

            when ( 'container' ) {
                $ref //= $point->ref;
                splice( @$ref, $_, $length, @$replace )
                  for reverse sort @$offset;
            }

            when ( 'idx' ) {
                my $parent = $point->parent->ref->$*;
                assert( is_arrayref( $parent ) );
                splice( @$parent, $idx + $_, $length, @$replace )
                  for reverse sort @$offset;
            }

        }


    }
}


sub _insert ( $use_dest_as, $points, $offset, $length, $src ) {

    for my $point ( @$points )  {

        my $ref;
        my $idx;

        my $use = $use_dest_as;
        if ( $use_dest_as eq 'auto' ) {

            $ref = $point->ref;

            $use
              = is_arrayref( $ref ) | is_hashref( $ref ) ? 'container'
              : defined( $idx = $point->attrs->{idx} ) ? 'idx'
              :   croak( "point is neither an array element nor an array ref\n" );
        }

        for ( $use ) {

            when ( 'container' ) {

                $ref //= $point->ref;

                for ( $ref ) {

                    when ( !!is_hashref( $ref ) ) {

                        croak(
                            "insertion into a hash requires an even number of elements\n"
                        ) if @$src % 2;

                        pairmap { ; $ref->{$a} = $b } @$src;
                    }

                    when ( !!is_arrayref( $ref ) ) {

                        splice( @$ref, $_ ? @$ref : 0, 0, @$src )
                          for reverse sort @$offset
                    }

                    default {
                        croak( "can't insert into a reference of type ",
                            ref $ref, "\n" );
                    }
                }
            }

            when ( 'idx' ) {
                my $parent = $point->parent->ref->$*;
                assert( is_arrayref( $parent ) );
                $idx //= $point->attrs->{idx};
                assert( defined $idx );
                splice( @$parent, $idx + $_, $length, @$src )
                  for reverse sort @$offset;
            }
        }


    }

}

sub _delete ( $points ) {

    for my $point ( @$points )  {


        my $parent = $point->parent->ref->$*;
        my $attr   = $point->attr;

        if ( exists $attr->{key} ) {
            delete $parent->{key};
        }
        elsif ( exists $attr->{idx} ) {

            splice( @$parent, $attr->{idx}, 1 );
        }
        else {
            croak( "destination was not an array or hash element?\n" );
        }

    }

}

sub _replace ( $points, $use_dest_as, $src ) {

    for my $point ( @$points )  {


        for ( $use_dest_as ) {

            when ( 'value' ) {
                $point->ref->$* = $src;
            }

            when ( 'key' ) {

                my $parent = $point->parent->ref->$*;
                croak( "key replacement requires a hash element\n" )
                  unless is_hashref( $parent );

                my $key = $point->attrs->{key};
                assert( defined $key );

                $parent->{$key} = is_ref( $src ) ? refaddr( $src ) : $src;
            }
        }

    }

}


1;

# COPYRIGHT

__END__


=head1 SYNOPSIS


=head1 SEE ALSO
