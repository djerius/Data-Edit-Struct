package Data::Edit::Struct;

# ABSTRACT: Edit a Perl structure addressed with a Data::DPath path

use strict;
use warnings;
use experimental qw[ postderef switch signatures ];

use Exporter 'import';

our $VERSION = '0.01';

use Ref::Util qw[ is_arrayref is_hashref is_scalarref is_ref is_coderef ];

use Types::Standard -types;
use Data::Edit::Struct::Types -types;

use custom::failures 'Data::Edit::Struct::failure' => [ qw{
      input::dest
      input::src
      input::param
      internal
      } ];

use List::Util qw[ pairmap ];
use Scalar::Util qw[ refaddr ];
use Params::ValidationCompiler qw[ validation_for ];
use Safe::Isa;

use Data::DPath qw[ dpath dpathr dpathi ];

# uncomment to run coverage tests, as Safe compartment makes
# Devel::Cover whimper
#
# $Data::DPath::USE_SAFE = 0;

our @EXPORT_OK = qw[ edit ];

my %dest = (
    dest  => { type => Context },
    dpath => { type => Str, default => '/' },
);

my %dtype = ( dtype => { type => UseDataAs, default => 'auto' }, );

my %source = (
    src   => { type => Any,       optional => 1 },
    spath => { type => Str,       optional => 1 },
    stype => { type => UseDataAs, default  => 'auto' },
    sxfrm => {
        type => Enum [ 'iterate', 'array', 'hash', 'error' ] | CodeRef,
        default => 'error'
    },
    sxfrm_args => {
        type    => HashRef,
        default => sub { {} },
    },
);

my %length = ( length => { type => Int, default => 1 } );
my %offset = (
    offset => {
        type    => Int,
        default => 0,
    } );

my %Validation = (
    pop    => { %dest, %length },
    shift  => { %dest, %length },
    splice => { %dest, %length, %offset, %source, %dtype },
    insert => {
        %dest, %length, %offset, %source, %dtype,
        insert => {
            type => Enum [ 'before', 'after' ],
            default => 'before',
        },
        anchor =>
          { type => Enum [ 'first', 'last', 'index' ], default => 'first' },
        pad => { type => Any, default => undef },
    },
    delete  => { %dest, %length },
    replace => {
        %dest, %source,
        replace => {
            type => Enum [ 'value', 'key', 'auto' ],
            default => 'auto',
        },

    },
);

my %Validator
  = map { $_ => validation_for( params => $Validation{$_}, name => $_ ) }
  keys %Validation;

sub dup_context ( $context ) {
    Data::DPath::Context->new( give_references => 1 )
      ->current_points( $context->current_points );
}


sub edit ( $action, $request ) {

    Data::Edit::Struct::failure::input::param->throw( "no action specified\n" )
      unless defined $action;

    defined( my $validator = $Validator{$action} )
      or Data::Edit::Struct::failure::input::param->throw(
        "unknown acton: $action\n" );

    my %arg = $validator->( %$request );

    my $src = _sxfrm( @arg{ qw[ src spath sxfrm sxfrm_args ] } );

    my $points
      = dup_context( $arg{dest} )->_search( dpathr( $arg{dpath} ) )
      ->current_points;

    for ( $action ) {

        when ( 'pop' ) {
            _pop( $points, $arg{length} );
        }

        when ( 'shift' ) {

            _shift( $points, $arg{length} );

        }

        when ( 'splice' ) {

            $src //= [ \[] ];

            _splice( $arg{dtype}, $points,
                $arg{offset}, $arg{length}, _deref( $_, $arg{stype} ) )
              foreach @$src;
        }

        when ( 'insert' ) {
            Data::Edit::Struct::failure::input::src->throw(
                "source was not specified" )
              if !defined $src;

            _insert( $arg{dtype}, $points, $arg{insert}, $arg{anchor},
                $arg{pad}, $arg{offset}, _deref( $_, $arg{stype} ) )
              foreach @$src;
        }


        when ( 'delete' ) {
            _delete( $points, $arg{length} );
        }

        when ( 'replace' ) {

            Data::Edit::Struct::failure::input::src->throw(
                "source was not specified" )
              if !defined $src;

            Data::Edit::Struct::failure::input::src->throw(
                "source path may not have multiple resolutions" )
              if @$src > 1;

            _replace( $points, $arg{replace}, $src->[0] );
        }
    }

}


sub _sxfrm ( $src, $spath, $sxfrm, $args ) {

    return unless defined $src;

    my $ctx;

    if ( $src->$_isa( 'Data::DPath::Context' ) ) {
        $ctx = dup_context( $src );
    }
    else {
        $spath //= is_arrayref( $src )
          || is_hashref( $src ) ? '/' : '/*[0]';
        $ctx = dpathi( $src );
        $ctx->give_references( 1 );
    }

    $spath = dpath( $spath );

    for ( $sxfrm ) {

        when ( !!is_coderef( $_ ) ) {

            return $_->( $ctx, $spath, $args );
        }

        when ( 'array' ) {
            $ctx->give_references( 0 );
            return [ \$ctx->matchr( $spath ) ];
        }

        when ( 'hash' ) {

            my %src;

            if ( exists $args->{key} ) {

		my $src = $ctx->matchr( $spath );
		Data::Edit::Struct::failure::input::src->throw(
							       "source path may not have multiple resolutions\n" )
		    if @$src > 1;
		$src{ $args->{key} } = $src->[0]->$*;
            }

            else {

                $ctx->give_references( 0 );
                for my $point ( $ctx->_search( $spath )->current_points->@* ) {

                    my $attrs = $point->attrs;
                    defined( my $key = $attrs->{key} // $attrs->{idx} )
                      or Data::Edit::Struct::failure::input::src->throw(
                        "source path returned multiple values; unable to convert into hash as element has no `key' or `idx' attribute\n"
                      );
                    $src{$key} = $point->ref->$*;
                }
            }

            return [ \\%src ];
        }

        when ( 'iterate' ) {

            return $ctx->matchr( $spath );

        }

        default {

            my $src = $ctx->matchr( $spath );
            Data::Edit::Struct::failure::input::src->throw(
                "source path may not have multiple resolutions\n" )
              if @$src > 1;

	    return $src;
        }

    }
}


sub _deref ( $ref, $stype ) {

    my $use = $stype;
    $use = is_ref( $$ref ) ? 'container' : 'element'
      if $use eq 'auto';

    for ( $use ) {

        when ( 'element' ) {

            return [$$ref];
        }

        when ( 'container' ) {

            return
                is_arrayref( $$ref )  ? $$ref
              : is_hashref( $$ref )   ? [%$$ref]
              : is_scalarref( $$ref ) ? [$$$ref]
              : Data::Edit::Struct::failure::input::src->throw(
                "\$value is not an array, hash, or scalar reference" );
        }

        default {

            Data::Edit::Struct::failure::internal->throw(
                "internal error: unknown mode to use source in: $_" );
        }

    }
}

sub _pop ( $points, $length ) {

    for my $point ( @$points ) {

        my $dest = $point->ref->$*;
        Data::Edit::Struct::failure::input::dest->throw(
            "destination is not an array" )
          unless is_arrayref( $dest );

        $length = @$dest if $length > @$dest;
        splice( @$dest, -$length, $length );

    }
}

sub _shift ( $points, $length ) {

    for my $point ( @$points ) {
        my $dest = $point->ref->$*;
        Data::Edit::Struct::failure::input::dest->throw(
            "destination is not an array" )
          unless is_arrayref( $dest );
        splice( @$dest, 0, $length );
    }
}

sub _splice ( $dtype, $points, $offset, $length, $replace ) {

    for my $point ( @$points ) {

        my $ref;

        my $attrs = $point->can( 'attrs' );

        my $idx = ( ( defined( $attrs ) && $point->$attrs ) // {} )->{idx};

        my $use = $dtype;

        if ( $use eq 'auto' ) {

            $ref = $point->ref;
            $use
              = is_arrayref( $$ref ) ? 'container'
              : defined $idx         ? 'element'
              : Data::Edit::Struct::failure::input::dest->throw(
                "point is neither an array element nor an array ref" );
        }

        for ( $use ) {

            when ( 'container' ) {
                $ref //= $point->ref;
                Data::Edit::Struct::failure::input::dest->throw(
                    "point is not an array reference" )
                  unless is_arrayref( $$ref );

                splice( $$ref->@*, $offset, $length, @$replace );
            }

            when ( 'element' ) {

                my $rparent = $point->parent;
                my $parent
                  = defined( $rparent )
                  ? $rparent->ref
                  : undef;

                Data::Edit::Struct::failure::input::dest->throw(
                    "point is not an array element" )
                  unless defined $$parent && is_arrayref( $$parent );

                splice( @$$parent, $idx + $offset, $length, @$replace );
            }

        }


    }
}


sub _insert ( $dtype, $points, $insert, $anchor, $pad, $offset, $src ) {

    for my $point ( @$points ) {

        my $ref;
        my $idx;
        my $attrs;

        my $use = $dtype;
        if ( $dtype eq 'auto' ) {

            $ref = $point->ref;

            $use
              = is_arrayref( $$ref )
              || is_hashref( $$ref ) ? 'container'
              : defined( $attrs = $point->can( 'attrs' ) )
              && defined( $idx = $point->attrs->{idx} ) ? 'element'
              : Data::Edit::Struct::failure::input::dest->throw(
                "point is neither an array element nor an array ref" );
        }

        for ( $use ) {

            when ( 'container' ) {

                $ref //= $point->ref;

                for ( $ref ) {

                    when ( !!is_hashref( $$ref ) ) {

                        Data::Edit::Struct::failure::input::src->throw(
                            "insertion into a hash requires an even number of elements\n"
                        ) if @$src % 2;

                        pairmap { ; $$ref->{$a} = $b } @$src;
                    }

                    when ( !!is_arrayref( $$ref ) ) {
                        _insert_via_splice( $insert, $anchor, $pad, $ref, 0,
                            $offset, $src );
                    }

                    default {
                        Data::Edit::Struct::failure::input::dest->throw(
                            "can't insert into a reference of type @{[ ref $$ref]}"
                        );
                    }
                }
            }

            when ( 'element' ) {
                my $rparent = $point->parent;
                my $parent
                  = defined( $rparent )
                  ? $rparent->ref
                  : undef;

                Data::Edit::Struct::failure::input::dest->throw(
                    "point is not an array element" )
                  unless defined $parent && is_arrayref( $$parent );

                $idx //= ( $attrs // $point->attrs )->{idx};

                _insert_via_splice( $insert, 'index', $pad, $parent, $idx,
                    $offset, $src );
            }
        }
    }
}

sub _insert_via_splice ( $insert, $anchor, $pad, $rdest, $idx, $offset, $src ) {

    my $fididx;

    for ( $anchor ) {

        $fididx = 0 when ( 'first' );
        $fididx = $$rdest->$#* when ( 'last' );
        $fididx = $idx when ( 'index' );

        default {
            Data::Edit::Struct::failure::internal->throw(
                "unknown insert anchor: $anchor" );
        }
    }

    # turn relative index into positive index
    $idx = $offset + $fididx;

    # make sure there's enough room.
    for ( $insert ) {

        my $maxidx = $$rdest->$#*;

        when ( 'before' ) {

            if ( $idx < 0 ) {
                unshift $$rdest->@*, ( $pad ) x ( -$idx );
                $idx = 0;
            }

            elsif ( $idx > $maxidx + 1 ) {
                push $$rdest->@*, ( $pad ) x ( $idx - $maxidx - 1 );
            }
        }

        when ( 'after' ) {

            if ( $idx < 0 ) {
                unshift $$rdest->@*, ( $pad ) x ( -$idx - 1 ) if $idx < -1;
                $idx = 0;
            }

            elsif ( $idx > $maxidx ) {
                push $$rdest->@*, ( $pad ) x ( $idx - $maxidx );
                ++$idx;
            }

            else {
                ++$idx;
            }

        }
    }

    splice( @$$rdest, $idx, 0, @$src );
}

sub _delete ( $points, $length ) {

    for my $point ( @$points ) {

        my $rparent = $point->parent;
        my $parent
          = defined( $rparent )
          ? $rparent->ref
          : undef;

        Data::Edit::Struct::failure::input::dest->throw(
            "point is not an element in a container" )
          unless defined $parent;

        my $attr = $point->attrs;

        if ( defined( my $key = $attr->{key} ) ) {
            delete $$parent->{$key};
        }
        elsif ( exists $attr->{idx} ) {

            splice( @$$parent, $attr->{idx}, $length );

        }
        else {
            Data::Edit::Struct::failure::input::internal->throw(
                "point has neither idx nor key attribute" );
        }

    }

}

sub _replace ( $points, $replace, $src ) {

    for my $point ( @$points ) {

        $replace = 'value'
          if $replace eq 'auto';

        for ( $replace ) {

            when ( 'value' ) {
                $point->ref->$* = $src->$*;
            }

            when ( 'key' ) {

                my $rparent = $point->parent;
                my $parent
                  = defined( $rparent )
                  ? $rparent->ref
                  : undef;

                Data::Edit::Struct::failure::input::dest->throw(
                    "key replacement requires a hash element\n" )
                  unless is_hashref( $$parent );

                my $old_key = $point->attrs->{key};

                my $new_key = is_ref( $$src ) ? refaddr( $$src ) : $$src;

                $$parent->{$new_key} = delete $$parent->{$old_key};
            }
        }

    }

}


1;

# COPYRIGHT

__END__


=head1 SYNOPSIS


=head1 SEE ALSO
