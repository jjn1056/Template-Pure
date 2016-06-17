
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

  sub new {
    my $class = shift;
    return $class->SUPER::new(@_,
      template => $class->template,
      directives => [$class->directives]);
  }

  sub inner_dom {
    my $self = shift;
    return $self->encoded_string(
      $self->{inner_dom}->content);
  }

  sub parent { shift->{parent} }
  sub children { @{shift->{children}} }

  sub add_child {
    my ($self, $child) = @_;
    push @{shift->{children}}, $child;
    return $self->children;
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

  package Local::Form;

  use Moo;
  use DateTime;

  extends 'Template::Pure::Component';

  sub template { q[<form></form>] }

  sub directives {
    'form' => 'self.inner_dom',
  }

  package Local::Input;

  use Moo;
  use DateTime;

  has a => (is=>'ro', required=>1);

  extends 'Template::Pure::Component';

  sub template { q[<input></input>] }

  sub directives {
    'input' => 'self.inner_dom',
    'input@href' => 'self.a',
  }
}

ok my $html_template = q[
  <html>
    <head>
      <title>Page Title: </title>
    </head>
    <body>
      <p>Time in NYC: <pure-timestamp tz='America/New_York'/></p>
      <p>Time in Chicago: <pure-timestamp tz='America/Chicago' /></p>
      <pure-form>
        <pure-input a='foo'/>
        <pure-input a='bar'/>
        <pure-input a='baz'/>
      </pure-form>

      <pure-code>
        <pure-timestamp tz='America/Chicago' />
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

ok my $pure = Template::Pure->new(
  components=>+{
    timestamp => sub {
      my ($self, %params) = @_;
      return Local::Timestamp->new(%params);
    },
    code => sub {
      my ($self, %params) = @_;
      return Local::Code->new(%params);
    },
    form => sub {
      my ($self, %params) = @_;
      return Local::Form->new(%params);
    },
    input => sub {
      my ($self, %params) = @_;
      return Local::Input->new(%params);
    },
    
  },
  template=>$html_template,
  directives=> [
    title => 'title',
  ]
);

ok my %data = (
  title => 'The Time',
);

ok my $string = $pure->render(\%data);
ok my $dom = Mojo::DOM58->new($string);

is $pure->initialized_components->{'timestamp-0'}->parent, undef;
is $pure->initialized_components->{'timestamp-0'}->children, ();
is $pure->initialized_components->{'timestamp-1'}->parent, undef;
is $pure->initialized_components->{'form-2'}->parent, undef;
is ref($pure->initialized_components->{'input-3'}->parent), 'Local::Form';
is ref($pure->initialized_components->{'input-4'}->parent), 'Local::Form';
is ref($pure->initialized_components->{'input-5'}->parent), 'Local::Form';
is $pure->initialized_components->{'code-6'}->parent, undef;
is $pure->initialized_components->{'code-6'}->children, 1;

is_deeply [ map { $_->{a} } $pure->initialized_components->{'input-3'}->parent->children ], 
  [qw/foo bar baz/];

warn $string;

done_testing;
