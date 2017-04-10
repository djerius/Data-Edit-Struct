package Data::Edit::Struct;

# ABSTRACT: Edit a Perl structure addressed with a Data::DPath path

use strict;
use warnings;
use experimental qw[ postderef switch signatures ];

use Exporter 'import';

our $VERSION = '0.02';

use Ref::Util qw[
  is_plain_arrayref is_arrayref
  is_plain_hashref  is_hashref
  is_scalarref is_ref is_coderef
];

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

## no critic(ProhibitSubroutinePrototypes)

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
    clone => {
        type    => Bool | CodeRef,
        default => 0
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

sub _dup_context ( $context ) {
    Data::DPath::Context->new( give_references => 1 )
      ->current_points( $context->current_points );
}



sub edit ( $action, $params ) {

    Data::Edit::Struct::failure::input::param->throw( "no action specified\n" )
      unless defined $action;

    defined( my $validator = $Validator{$action} )
      or Data::Edit::Struct::failure::input::param->throw(
        "unknown acton: $action\n" );

    my %arg = $validator->( %$params );

    my $src = _sxfrm( @arg{qw[ src spath sxfrm sxfrm_args ]} );

    my $points
      = _dup_context( $arg{dest} )->_search( dpathr( $arg{dpath} ) )
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

            _splice( $arg{dtype}, $points, $arg{offset}, $arg{length},
                _deref( $_, $arg{stype}, $arg{clone} ) )
              foreach @$src;
        }

        when ( 'insert' ) {
            Data::Edit::Struct::failure::input::src->throw(
                "source was not specified" )
              if !defined $src;

            _insert( $arg{dtype}, $points, $arg{insert}, $arg{anchor},
                $arg{pad}, $arg{offset},
                _deref( $_, $arg{stype}, $arg{clone} ) )
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
        $ctx = _dup_context( $src );
    }
    else {
        if ( !defined $spath ) {

            if (   is_plain_arrayref( $src )
                || is_plain_hashref( $src ) )
            {
                $spath = '/';
            }

            else {
                $src   = [$src];
                $spath = '/*[0]';
            }
        }

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


sub _clone ( $ref ) {

    require Storable;

    return Storable::dclone( $ref );
}

sub _deref ( $ref, $stype, $clone ) {

    $stype = is_plain_arrayref( $$ref )
      || is_plain_hashref( $$ref ) ? 'container' : 'element'
      if $stype eq 'auto';

    my $struct;
    for ( $stype ) {

        when ( 'element' ) {
            $struct = [$$ref];
        }

        when ( 'container' ) {

            $struct
              = is_arrayref( $$ref ) ? $$ref
              : is_hashref( $$ref )  ? [%$$ref]
              : Data::Edit::Struct::failure::input::src->throw(
                "\$value is not an array or hash reference" );
        }

        default {

            Data::Edit::Struct::failure::internal->throw(
                "internal error: unknown mode to use source in: $_" );
        }

    }

    $clone = \&_clone unless is_coderef( $clone ) || !$clone;

    return
        is_coderef( $clone ) ? $clone->( $struct )
      : $clone               ? _clone( $struct )
      :                        $struct;

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
              = is_plain_arrayref( $$ref ) ? 'container'
              : defined $idx               ? 'element'
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
              = is_plain_arrayref( $$ref )
              || is_plain_hashref( $$ref ) ? 'container'
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

# EXAMPLE: ./examples/synopsis.pl

=head1 DESCRIPTION

B<Data::Edit::Struct> provides a high-level interface for editing data
within complex data structures.  Edit and source points are specified
via L<Data::DPath> paths.

The I<destination> structure is the structure to be edited.  If data
are to be inserted into the structure, they are extracted from the
I<source> structure.  See L</Data Copying> for the copying policy.

The following actions may be performed on the destination structure:

=over

=item  * C<pop> - remove one or more elements from the bottom of an array

=item  * C<shift> - remove one or more elements from the top of an array

=item  * C<splice> - invoke C<splice> on an array

=item  * C<insert> - insert elements into an array or a hash

=item  * C<delete> - delete array or hash elements

=item  * C<replace> - replace array or hash elements (and in the latter case keys)

=back

=head2 Elements I<vs.> Containers

B<Data::Edit::Struct> operates on elements in the destination
structure by following a L<Data::DPath> path.  For example, if

# EXAMPLE: ./examples/ex1_0.pl

then a data path of

 /bar/*[0]

identifies the first element in the C<bar> array.  That element may be
treated either as a I<container> or as an I<element> (this is
specified by the L</dtype> option).

In the above example, C<< $dest->{bar}[0] >> resolves to a scalar, so
by default it is treated as an element.  However C<< $dest->{bar[1]}
>> resolves to a hashref.  When operating on it, should it be treated
as an opaque object, or as container?  For example,

# EXAMPLE: ./examples/ex1_1.pl

Should C<$src> be inserted I<into> element 2, as in

# COMMAND: perl ./examples/run ex1_0.pl ex1_1.pl  dump_dest.pl

or should it be inserted I<before> element 2 in C<bar>, as in?

# COMMAND: perl ./examples/run ex1_0.pl ex1_2.pl  dump_dest.pl

The first behavior treats it as a I<container>, the second as an
I<element>.  By default destination paths which resolve to hash or
array references are treated as B<containers>, so the above code
generates the first behavior.  To explicitly indicate how a path
should be treated, use the C<< dtype >> option.  For example,

# EXAMPLE: ./examples/ex1_2.pl

results in

# COMMAND: perl ./examples/run ex1_0.pl ex1_2.pl  dump_dest.pl

Source structures may have the same ambiguity. In the above example,
note that the I<contents> of the hash in the source path are inserted,
not the reference itself.  This is because non-blessed references in
sources are by default considered to be containers, and their contents
are copied.  To treat a source reference as an opaque element, use the
L</stype> option to specify it as such:

# EXAMPLE: ./examples/ex1_3.pl

which results in

# COMMAND: perl ./examples/run ex1_0.pl ex1_3.pl  dump_dest.pl

Note that C<dpath> was set to I<element>, otherwise C<edit> would have
attempted to insert the source hashref (not its contents) into the
destination hash, which would have failed, as insertion into a hash
requires a multiple of two elements (i.e., C<< $key, $value >>).

=head2 Source Transformations

Data extracted from the source structure may undergo transformations
prior to being inserted into the destination structure.  There are
several predefined transformations and the caller may specify a
callback to perform their own.

Most of the transformations have to do with multiple values being
returned by the source path.  For example,

# EXAMPLE: ./examples/sxfrm1_0.pl

would result in multiple extracted values:

# COMMAND: perl ./examples/run examples/sxfrm1_0.pl  examples/sxfrm1_1.pl

By default multiple values are not allowed, but a source
transformation (specified by the C<sxfrm> option ) may be used to
change that behavior.  The provided transforms are:

=over

=item C<array>

The values are assembled into an array.  The C<stype>
parameter is used to determine whether that array is treated as a
container or an element.

=item C<hash>

The items are assembled into a hash.  The C<stype> parameter is used
to determine whether that array is treated as a container or an
element.  Keys are derived from the data:

=over

=item * Keys for hash values will be their hash keys

=item * Keys for array values will be their array indices

=back

If there is a I<single> value, a hash key may be specified via the
C<key> option to the C<sxfrm_args> option.

=item C<iterate>

The edit action is applied independently to each source value in turn.


=item I<coderef>

If C<sxfrm> is a code reference, it will be called to generate the
source values.  See L</Source Callbacks> for more information.

=back


=head2 Source Callbacks

If the C<sxfrm> option is a code reference, it is called to generate
the source values.  It must return an array which contains I<references>
to the values (even if they are already references).  For example,
to return a hash:

  my %src = ( foo => 1 );
  return [ \\%hash ];

It is called with the arguments

=over

=item C<$ctx>


A L</Data::DPath::Context> object representing the source structure.

=item C<$spath>

The source path.  Unless otherwise specified, this defaults to C</>,
I<except> when the source is not a plain array or plain
hash, in which case the source is embedded in an array, and C<spath> is set to C</*[0]>.

This is because L</Data::DPath> requires a container to be at the root
of the source structure, and anything other than a plain array or hash
is most likely a blessed object or a scalar, both of which should be
treated as elements.

=item C<$args>

The value of the C<sxfrm_args> option.

=back

=head2 Data Copying

By defult, copying of data from the source structure is done
I<shallowly>, e.g. references to arrays or hashes are not copied
recursively.  This may cause problems if further modifications are
made to the destination structure which may, through references,
alter the source structure.

For example, given the following input structures:

# EXAMPLE: ./examples/copy1_0.pl

and this edit operation:

# EXAMPLE: ./examples/copy1_1.pl

We get a destination structure that looks like this:

# COMMAND: perl ./examples/run copy1_0.pl copy1_1.pl  dump_dest.pl

But if later we change C<$dest>,

# EXAMPLE: ./examples/copy1_2.pl

the source structure is also changed:

# COMMAND: perl ./examples/run copy1_0.pl copy1_1.pl  copy1_2.pl dump_src.pl

To avoid this possible problem, C<Data::Edit::Struct> can be passed
the L<< C<clone|/edit/clone> >> option, which will instruct it how to
copy data.


=head1 SUBROUTINES

=head2  edit ( $action, $params )

Edit a data structure.  The available actions are discussed below.

Destination structure parameters are:

=over

=item C<dest>

A reference to a structure or a L<< Data::DPath::Context >> object.

=item C<dpath>

A string representing the data path. This may result in multiple
extracted values from the structure; the action will be applied to
each in turn.

=item C<dtype>

May be C<auto>, C<element> or C<container>, to treat the extracted
values either as elements or containers.  If C<auto>, non-blessed
arrays and hashes are treated as containers.

=back

Some actions require a source structure; parameters related
to that are:

=over

=item C<src>

A reference to a structure or a L<Data::DPath::Context> object.

=item C<spath>

A string representing the data path. This may result in multiple
extracted values from the structure; the action will be applied to
each in turn.

=item C<stype>

May be C<auto>, C<element> or C<container>, to treat the extracted
values either as elements or containers.  If C<auto>, non-blessed
arrays and hashes are treated as containers.


=item C<clone>

This may be a boolean or a code reference.  If a boolean, and true,
L<Storable/dclone> is used to clone the source structure.  If set to a
code reference, it is called with a I<reference> to the structure to
be cloned.  It should return a I<reference> to the cloned structure.

=back

Actions may have additional parameters

=head3 C<pop>

Remove one or more elements from the end of an array.  The destination
structure must be an array. Additional parameters are:


=over

=item C<length>

The number of elements to remove.  Defaults to C<1>.

=back


=head3 C<shift>

Remove one or more elements from the front of an array.  The
destination structure must be an array. Additional parameters are:


=over

=item C<length>

The number of elements to remove.  Defaults to C<1>.

=back


=head3 C<splice>

Perform a L<splice|perlfunc/splice> operation on an array, e.g.

  splice( @$dest, $offset, $length, @$src );

The C<$offset> and C<$length> parameters are provided by the C<offset>
and C<length> options.

The destination structure may be an array or an array element.  In the
latter case, the actual offset passed to splice is the sum of the
index of the array element and the value provided by the C<offset>
option.

A source structure is optional, and may be an array or a hash.

=head3 C<insert>

Insert a source structure into the destination structure.  The result
depends upon whether the point at which to insert is to be treated as
a container or an element.

=over

=item container

=over

=item Hash

If the container is a hash, the source must be a container (either
array or hash), and must contain an even number of elements.  Each
sequential pair of values is treated as a key, value pair.

=item Array

If the container is an array, the source may be either a container or
an element. The following options are available:

=over

=item C<offset>

The offset into the array of the insertion point.  Defaults to C<0>.
See L</anchor>.

=item C<anchor>

Indicates which end of the array the C<offset> parameter is relative to.
May be C<first> or C<last>.  It defaults to C<first>.

=item C<pad>

If the array must be enlarged to accomodate the specified insertion point, fill the new
values with this value.  Defaults to C<undef>.

=item C<insert>

Indicates which side of the insertion point data will be inserted. May
be either C<before> or C<after>.  It defaults to C<before>.

=back

=back

=item element

The insertion point must be an array value. The source may be either a
container or an element. The following options are avaliable:

=over

=item C<offset>

Move the insertion point by this value.

=item C<pad>

If the array must be enlarged to accomodate the specified insertion point, fill the new
values with this value.  Defaults to C<undef>.

=item C<insert>

Indicates which side of the insertion point data will be inserted. May
be either C<before> or C<after>.  It defaults to C<before>.

=back

=back

=head2 C<delete>

Remove an array or hash value.

=head2 C<replace>

Replace an array or hash element, or a hash key. The source data is
always treated as an element. It takes the following options:

=over


=item C<replace>

Indicates which part of a hash element to replace, either C<key> or
C<value>.  Defaults to C<value>.  If replacing the key and the source
value is a reference, the value returned by
L<Scalar::Util::refaddr|Scalar::Util/reffadr> will be used.

=back
