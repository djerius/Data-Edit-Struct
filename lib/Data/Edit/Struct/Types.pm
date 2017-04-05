package  Data::Edit::Struct::Types;

# ABSTRACT: Types for Data::Edit::Struct;

use strict;
use warnings;

our $VERSION = '0.01';

use Data::DPath qw[ dpath dpathi ];
use Type::Library
  -base,
  -declare => qw( Context UseDataAs IntArray DataPath );
use Type::Utils -all;
use Types::Standard -types;



declare Context,
  as InstanceOf ['Data::DPath::Context'],;

coerce Context,
  from HashRef | ArrayRef | ScalarRef, via sub { dpathi( $_ ) };

declare UseDataAs,
  as Enum [ 'element', 'container', 'auto' ];

declare IntArray,
  as ArrayRef[Int];

coerce IntArray,
  from Int, via sub { [ $_ ] };


1;


1;

# COPYRIGHT

__END__


=head1 SYNOPSIS


=head1 SEE ALSO
