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

sub next {
  my ($self) = @_;
  return $self->{_next}->($self);
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


sub max_index {  }



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
