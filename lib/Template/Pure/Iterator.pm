use warnings;
use strict;

package Template::Pure::Iterator;

use Scalar::Util 'blessed';

sub from_proto {
  my ($class, $proto) = @_;
  if(blessed $proto) {
    return $class->from_object($proto);
  } else {
    my $type = 'from_' .lc ref $proto;
    return $class->$type($proto);
  }
}

sub from_array {
  my ($class, $arrayref) = @_;
  my $index = 0;
  return bless +{
    _index => sub { return $index },
    _max_index => sub { return $#{$arrayref} },
    _count => sub { return scalar @{$arrayref} },
    _next => sub {
      my $value = $arrayref->[$index];
      $index++;
      return $value;
    },
    _peek => sub { return $arrayref->[$index+pop] },
    _reset => sub { $index = 0 },
    _all => sub { return @{$arrayref} },
  }, $class;
}

sub next {
  my ($self) = @_;
  return $self->{_next}->($self);
}

sub peek {
  my ($self, $positions) = @_;
  return $self->{_peek}->($self, $positions);
}

sub reset {
  my ($self) = @_;
  return $self->{_reset}->($self);
}

sub all {
  my ($self) = @_;
  return $self->{_all}->($self);
}

sub count {
  my ($self) = @_;
  return $self->{_count}->($self);
}

sub slice {
  my ($self) = @_;
  return $self->{_slice}->($self);
}

sub index {
  my ($self) = @_;
  return $self->{_index}->($self);
}

sub max_index {
  my ($self) = @_;
  return $self->{_max_index}->($self);
}



sub pager { }

sub page { }

sub apply_sorting { }

sub apply_filter { }

sub is_ordered { }

sub is_first { }

sub is_last { }

sub is_even { }

sub is_odd { }

sub is_paged { }

1;
