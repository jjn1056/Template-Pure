use strict;
use warnings;

package Template::Pure::DataContext;
 
use Scalar::Util 'blessed';
use Template::Pure::UndefObject;
use Data::Dumper;

use overload
  q{""} => sub { shift->value },
  'fallback' => 1;

sub new {
  my ($proto, $data_proto, $root) = @_;
  my $class = ref($proto) || $proto;
  return bless +{
    value => $data_proto,
    root => ($root||$data_proto),
  }, $class;
}

sub value { shift->{value} }
 
sub at {
  my ($self, %at) = @_;
  my $current = $at{absolute} ? $self->{root} : $self->{value};
  foreach my $at(@{$at{path}}) {
    my $key = $at->{key} || die "missing key";
    if(blessed $current) {
      if($current->can($key)) {
        $current = $current->$key;
      } elsif($at->{optional}) {
        $current = undef;
      } else {
        die "Missing path '$key' in data context ". Dumper($current);
      }
    } elsif(ref $current eq 'HASH') {
      if(exists $current->{$key}) {
        $current = $current->{$key};
      } elsif($at->{optional}) {
        $current = undef;
      } else {
        warn Dumper $at;
        die "Missing path '$key'";
      }
    } else {
      die "Can't find path '$key' in ". Dumper $current;
    }
    if($at->{maybe}) {
      $current = Template::Pure::UndefObject->maybe($current);
    }
  }
  return $self->new($current, $self->{root});
}

1;

