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

use Carp;

our @EXPORT_OK = qw[ edit ];

my %dest = (
    dest  => { type => Context },
    dpath => { type => Str, default => '/' },
);

my %use_dest_as
  = ( use_dest_as => { type => Enum [ 'idx', 'ref' ], default => 'auto' } );

my %source = (
    source        => { type => Context,     optional => 1 },
    spath         => { type => Str,         default  => '/' },
    use_source_as => { type => UseSourceAs, default  => 'auto' },
);

my %length = ( length => { type => Int, default  => 1 } );
my %offset = ( offset => { type => Int, optional => 1 } );


my %Validation = (
    pop    => { %dest, %length },
    shift  => { %dest, %length },
    splice => { %dest, %length, %offset, %source, %use_dest_as },
    insert => { %dest, %length, %offset, %source, %use_dest_as },
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
        my $ctx = dup_context( $arg{src} );
        my @src = $ctx->search( $arg{spath} );
        croak( "source path may not have multiple resolutions\n" )
          if @src > 1;

        my $value = pop @src;

        my $use = $arg{use_source_as};
        $use = is_ref( $value ) ? 'ref' : 'value'
          if $use eq 'auto';

        $src
          = $arg{use_source_as} eq 'value' ? [$value]
          : is_arrayref( $value )          ? $value
          : is_hashref( $value )           ? [%$value]
          : is_scalarref( $value )         ? [$$value]
          : croak( "don't know how to dereference thing of ref '",
            ref $value, "\n" );
    }

    my $iter = dup_context( $arg{dest} )->isearch( $arg{dpath} );


    for ( $action ) {

        when ( 'pop' ) {

            while ( $iter->isnt_exhausted ) {
                croak( "pop destination is not an array\n" )
                  unless is_arrayref( $arg{dest} );
		my $dest = $iter->value->deref;
		my $length = $arg{length};
		$length = @$dest if $length > @$dest;
                splice( @$dest, -$length, $length );
            }

        }

        when ( 'shift' ) {

            while ( $iter->isnt_exhausted ) {
                my $dest = $iter->value->deref;
                croak( "pop destination is not an array\n" )
                  unless is_arrayref( $dest );
                splice( @$dest, 0, $arg{length} );
            }

        }

        when ( 'splice' ) {
            _splice( $arg{use_dest_as}, $iter,
                $arg{offset}, $arg{length}, $arg{src} );
        }

        when ( 'insert' ) {
            _insert( $arg{use_dest_as}, $iter, $arg{offset}, $arg{length},
                $arg{src} );
        }


        when ( 'delete' ) {
            _delete( $iter );
        }

        when ( 'replace' ) {
            _replace( $iter, $arg{use_dest_as}, $arg{src} );
        }
    }

}


sub _splice ( $use_dest_as, $iter, $offset, $length, $replace ) {

    while ( $iter->isnt_exhausted ) {

        my $point = $iter->value;
        my $ref;

        my $idx = $point->attrs->{idx};

        my $use = $use_dest_as;

        if ( $use_dest_as eq 'auto' ) {

            $ref = $point->ref;
            $use
              = is_arrayref( $ref ) ? 'ref'
              : defined $idx        ? 'idx'
              :   croak( "point is neither an array element nor an array ref\n" );
        }

        for ( $use ) {

            when ( 'ref' ) {
                $ref //= $point->ref;
                splice( @$ref, $offset, $length, @$replace );
            }

            when ( 'idx' ) {
                my $parent = $point->parent->ref->$*;
                assert( is_arrayref( $parent ) );
                splice( @$parent, $idx + $offset, $length, @$replace );
            }

        }


    }
}


sub _insert ( $use_dest_as, $iter, $offset, $length, $src ) {

    while ( $iter->isnt_exhausted ) {

        my $point = $iter->value;
        my $ref;

        my $idx;

        my $use = $use_dest_as;
        if ( $use_dest_as eq 'auto' ) {

            $ref = $point->ref;

            $use
              = is_arrayref( $ref ) | is_hashref( $ref ) ? 'ref'
              : defined( $idx = $point->attrs->{idx} ) ? 'idx'
              :   croak( "point is neither an array element nor an array ref\n" );
        }

        for ( $use ) {

            when ( 'ref' ) {

                $ref //= $point->ref;

                for ( $ref ) {

                    when ( !!is_hashref( $ref ) ) {

                        croak(
                            "insertion into a hash requires an even number of elements\n"
                        ) if @$src % 2;

                        pairmap { ; $ref->{$a} = $b } @$src;
                    }

                    when ( !!is_arrayref( $ref ) ) {

                        splice( @$ref, $offset ? @$ref : 0, 0, @$src );
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
                splice( @$parent, $idx + $offset, $length, @$src );
            }
        }


    }

}

sub _delete ( $iter ) {

    while ( $iter->isnt_exhausted ) {

        my $point  = $iter->value;
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

sub _replace ( $iter, $use_dest_as, $src ) {

    while ( $iter->isnt_exhausted ) {

        my $point = $iter->value;

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
