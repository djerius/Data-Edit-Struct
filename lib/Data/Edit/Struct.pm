package Data::Edit::Struct;

# ABSTRACT: Edit a Perl structure addressed with a Data::DPath path

use strict;
use warnings;
use experimental qw[ postderef switch signatures ];

use Exporter 'import';

our $VERSION = '0.01';

use Ref::Util qw[ is_arrayref is_hashref is_scalarref is_ref ];

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
);

my %length = ( length => { type => Int, default => 1 } );
my %offset = (
    offset => {
        type    => IntArray,
        default => sub { [0] }
    } );

my %sxfrm = (
    sxfrm => {
        type => Enum [ 'iterate', 'array', 'hash', 'error' ],
        default => 'error'
    } );

my %Validation = (
    pop    => { %dest, %length },
    shift  => { %dest, %length },
    splice => { %dest, %length, %offset, %source, %dtype, %sxfrm },
    insert => { %dest, %length, %offset, %source, %dtype, %sxfrm },
    delete  => { %dest, %length, %offset, },
    replace => {
        %dest, %source,
        %sxfrm,
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

    my $src;

    if ( exists $arg{src} ) {

        my $ctx;

        if ( $arg{src}->$_isa( 'Data::DPath::Context' ) ) {
            $ctx = dup_context( $arg{src} );
        }
        else {
            $arg{spath} //= is_arrayref( $arg{src} )
              || is_hashref( $arg{src} ) ? '/' : '/*[0]';
            $ctx = dpathi( $arg{src} );
            $ctx->give_references( 1 );
        }

        my $spath = dpath( $arg{spath} );

        for ( $arg{sxfrm} ) {

            when ( 'array' ) {
                $ctx->give_references( 0 );
                $src = [ \$ctx->matchr( $spath ) ];
            }

            when ( 'hash' ) {

                my %src;

                $ctx->give_references( 0 );
                for my $point ( $ctx->_search( $spath )->current_points->@* ) {

                    my $attrs = $point->attrs;
                    defined( my $key = $attrs->{key} // $attrs->{idx} )
                      or Data::Edit::Struct::failure::input::src->throw(
                        "source path returned multiple values; unable to convert into hash as element has no `key' or `idx' attribute\n"
                      );
                    $src{$key} = $point->ref->$*;
                }

                $src = [ \\%src ];
            }

            when ( 'iterate' ) {
                $src = $ctx->matchr( $spath );
            }

            default {

                $src = $ctx->matchr( $spath );
                Data::Edit::Struct::failure::input::src->throw(
                    "source path may not have multiple resolutions\n" )
                  if @$src > 1;
            }

        }

    }

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

            _insert( $arg{dtype}, $points, $arg{offset},
                _deref( $_, $arg{stype} ) )
              foreach @$src;
        }


        when ( 'delete' ) {
            _delete( $points, $arg{offset}, $arg{length} );
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

                splice( $$ref->@*, $_, $length, @$replace )
                  for reverse sort @$offset;
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

                splice( @$$parent, $idx + $_, $length, @$replace )
                  for reverse sort @$offset;
            }

        }


    }
}


sub _insert ( $dtype, $points, $offset, $src ) {

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

                        my $array_length = scalar @$$ref;
                        splice( @$$ref, $_, 0, @$src )
                          for reverse sort map { $_ == -1 ? $array_length : $_ }
                          @$offset;
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

                my $array_length = scalar @$$parent;
                splice( @$$parent, $idx + $_, 0, @$src )
                  for reverse sort map { $_ == -1 ? $array_length - $idx : $_ }
                  @$offset;
            }
        }


    }

}

sub _delete ( $points, $offset, $length ) {

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

            splice( @$$parent, $attr->{idx} + $_, $length )
              for reverse sort @$offset;

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
