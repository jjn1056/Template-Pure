use Test::Most;
use Template::Pure;

{
  package Lace::Component;

  use Moo::Role;
  use Template::Pure

  requires 'template', 'directives';

  has pure => (
    is=>'ro',
    lazy=>1,
    builder=>'_build_pure',
    handles => ['render'],
  );

  sub _build_pure {
    my ($self) = @_;
    return Template::Pure->new(
      template=>$self->template,
      directives=>[$self->directives])
  }

  sub on_load { }
  sub on_attach {  }

  sub process {
    my ($self, $dom, $data) = @_;
    $dom->replace(
      $self->render({
        'self' => $self,
        'data' => $data,
    }));
  }

  package Lace::Component::Localtime;

  use Moo;
  use DateTime;
  
  with 'Lace::Component';

  has 'tz' => (is=>'ro', predicate=>'has_tz');

  sub template {
    q[<span>time</span>];
  }

  sub directives {
    'span' => 'self.time',
  }

  sub time {
    my ($self) = @_;
    my $now = DateTime->now;
    $now->set_time_zone($self->tz)
      if $self->has_tz;
    return $now;
  }
}

ok my $html_template = qq[
  <?pure-wrap on='^body' src='wrapper.html'?>
  <?pure-component src='Localtime' as='pure-localtime'?>
  <html>
    <head>
      <title>Page Title: </title>
    </head>
    <body>
      <p>Time in NYC: <pure-localtime tz='America/New_York'/></p>
      <p>Time in Chicago: <pure-localtime tz='America/Chicago' /></p>
    </body>
  </html>
];

ok my $pure = Template::Pure->new(
  template=>$html_template,
  directives=> [
    title => 'title',
    'pure-localtime|' => sub {
      my ($t, $dom, $data) = @_;
      my $localtime = Lace::Component::Localtime->new(%{$dom->attr||+{}});
      $localtime->process($dom, $data);
    }
  ]
);

ok my %data = (
  title => 'The Time',
);

ok my $string = $pure->render(\%data);
ok my $dom = DOM::Tiny->new($string);

warn $string;

done_testing;
