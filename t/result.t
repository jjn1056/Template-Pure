
BEGIN {
  use Test::Most;
  use Template::Pure;
  plan skip_all => "Moo required, err $@" 
    unless eval "use Moo; 1";
  plan skip_all => "Digest::MD5 required, err $@" 
    unless eval "use Digest::MD5; 1";  
}

{
  package Template::Pure::Component;

  use Template::Pure;
  use Digest::MD5 qw(md5_hex);

  use base 'Template::Pure';

  sub component {
    my $class = shift;
    return $class->new(@_,
      template => $class->template,
      directives => [$class->directives]);
  }

  sub apply {
    my ($self, $dom, $data) = @_;
    $dom->replace(
      $self->render({
        'data' => $data,
    }));

    if(my($md5, $style) = $self->style_fragment) {
     unless($dom->root->at("style#$md5")) {
        $dom->root->at('head')->append_content("$style\n");
       }  
    }
    if(my($md5, $script) = $self->script_fragment) {
     unless($dom->root->at("script#$md5")) {
        $dom->root->at('head')->append_content("$script\n");
       }  
    }
  }

  sub inner_dom { return shift->{inner_dom} }
  sub parent { shift->{parent} }
  sub subcomponents { @{shift->subcomponents} }

  sub push_subcomponents {
    my ($self, $subcomponent) = @_;
    push @{shift->{subcomponents}}, $subcomponent;
    return $self->subcomponents;
  }

  sub style { }
  sub script { }
  sub template { }
  sub directives { }

  sub style_fragment {
    my $style = $_[0]->style;
    return unless $style;
    my $checksum = md5_hex($style);
    return $checksum, "<style type='text/css' id='$checksum'>$style</style>";
  }

  sub script_fragment {
    my $script = $_[0]->script;
    return unless $script;
    my $checksum = md5_hex($script);
    return $checksum, "<script type='text/javascript' id='$checksum'>$script</script>";
  }

  package Template::Pure::HasComponents;

  use Moo;
 
  extends 'Template::Pure';

  my %registered_comps = ();
  
  sub build_component {
    my ($self, $name, %params) = @_;
    return $name->component(%params);
  }

  around '_process_pi', sub {
    my ($orig, $class, $placeholder_cnt, $item, $num, @directives) = @_;
    # if($item->type eq 'pi' and $
    warn $item->tag if $item->tag;
    return $class->$orig($placeholder_cnt, $item, $num, @directives);
  };
  
  package Local::Timestamp;

  use Moo;
  use DateTime;

  extends 'Template::Pure::Component';

  has 'tz' => (is=>'ro', predicate=>'has_tz');

  sub style {q[
    .timestamp {
      color: blue;
    }
  ]}

  sub script {q[
    function hello() {
      alert('Hi');
    } 
  ]}

  sub template {
    q[<span class='timestamp' onclick="hello()">time</span>];
  }

  sub directives {
    '.timestamp' => 'self.time',
  }

  sub time {
    my ($self) = @_;
    my $now = DateTime->now;
    $now->set_time_zone($self->tz)
      if $self->has_tz;
    return $now;
  }

  package Local::Code;

  use Moo;
  use DateTime;

  extends 'Template::Pure::Component';

  sub template { q[<pre></pre>] }

  sub directives {
    'pre' => 'self.inner_dom',
  }
}

ok my $html_template = q[
  <?pure-component src='Local::Timestamp' as='pure-timestamp' ctx='settings.time'?>
  <html>
    <head>
      <title>Page Title: </title>
    </head>
    <body>
      <p>Time in NYC: <pure-timestamp tz='America/New_York'/></p>
      <p>Time in Chicago: <pure-timestamp tz='America/Chicago' /></p>
      <pure-code>
      package Example::User;

      use Moose;

      has 'first_name' => (is=>'ro');
      has 'last_name' => (is=>'ro');

      sub output {
        my $self = shift;
        print "Hi there ${\$self->first_name} ${\$self->last_name}!";
      }

      __PACKAGE__->meta->make_immutable;
      </pure-code>
    </body>
  </html>
];

ok my $pure = Template::Pure::HasComponents->new(
  template=>$html_template,
  directives=> [
    title => 'title',
    'pure-code|' => sub {
      my ($t, $dom, $data) = @_;
      my %params = (
        %{$dom->attr||+{}},
        inner_dom => $dom->content,
      );
      my $code = $t->build_component('Local::Code', %params);
      $code->apply($dom, $data);
    },
    'pure-timestamp|' => sub {
      my ($t, $dom, $data) = @_;
      my %params = (
        %{$dom->attr||+{}},
        inner_dom => $dom->content,
      );
      my $timestamp = $t->build_component('Local::Timestamp', %params);
      $timestamp->apply($dom, $data);
    }
  ]
);

ok my %data = (
  title => 'The Time',
);

ok my $string = $pure->render(\%data);
ok my $dom = Mojo::DOM58->new($string);

#warn $string;


done_testing;
