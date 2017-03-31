package  Data::Edit::Struct::Types;
use Data::DPath qw[ dpathi ];
use Type::Library
  -base,
  -declare => qw( Context UseSourceAs );
use Type::Utils -all;
use Types::Standard -types;



declare Context,
  as InstanceOf ['Data::DPath::Context'],;

coerce Context,
  from HashRef | ArrayRef | ScalarRef, via sub { dpathi( $_ ) };

declare UseSourceAs,
  as Enum [ 'value', 'container', 'auto' ],
  from Str,  q[ $UseSourceAs{$_} // $_ ];

declare IntArray,
  as ArrayRef[Int];

coerce IntArray,
  from Int, via sub { [ $_ ] };

1;

