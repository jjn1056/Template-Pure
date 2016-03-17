use strict;
use warnings;

package Template::Pure::DataProxy;

use Scalar::Util;
use Data::Dumper;

sub new {
  my ($proto, $data, %extra) = @_;
  my $class = ref($proto) || $proto;
  bless +{
    data => $data,
    extra => \%extra,
  }, $class;
}

sub can { 1 } # Evil, sorry

sub AUTOLOAD {
  return if our $AUTOLOAD =~ /DESTROY/;
  my $self = shift;
  ( my $method = $AUTOLOAD ) =~ s{.*::}{};
  if(Scalar::Util::blessed $self->{data}) {
    die "Proxy inside Proxy..." if $self->{data}->isa(ref $self);
    if($self->{data}->can($method)) {
      return $self->{data}->$method;
    } elsif(exists $self->{extra}{$method}) {
      return $self->{extra}{$method};
    } else {
      die "No value at $method for $self";
    }
  } else {
    ## I think we can assume its a hashref then.
    if(exists $self->{data}{$method}) {
      return $self->{data}{$method};
    } elsif(exists $self->{extra}{$method}) {
      return $self->{extra}{$method};
    } else {
      die "No value at $method in: ".Dumper $self;
    }
  }
}

1;

