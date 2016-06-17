
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

  sub apply {
    my ($self, $dom, $data) = @_;
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
    return $self->render({data=>$data});
  }

  sub inner_dom { return shift->{inner_dom} }
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

  package Template::Pure::HasComponents;

  use Moo;
 
  extends 'Template::Pure';


  has 'components' => (is=>'ro');
  
  my %initialized_components;

  sub initialized_components { %initialized_components }

  sub initialize_component {
    my ($self, $name, %params) = @_;
    return ($self->components->{$name} || return)->($self, %params);
  }

  around '_process_node', sub {
    #my %params = (cnt=>0, node=>$node, directives=>\@directives);
    my ($orig, $self, %params) = @_;
    $params{component_current_parent} = [] unless defined $params{component_current_parent};
    
    use Devel::Dwarn;
    Dwarn([map { ref $_ } @{$params{component_current_parent}}])
      if defined $params{component_current_parent};

    if(my ($component_name) = (($params{node}->tag||'') =~m/^pure\-(.+)?/)) {
      my %fields = (
        %{$params{node}->attr||+{}},
        parent => $params{component_current_parent}[-1]||undef,
        inner_dom => $params{node}->content,
      );
      my $component_id = $component_name.'-'.$params{cnt};
      $initialized_components{$component_id} = $self->initialize_component($component_name, %fields);
      $params{component_current_parent}[-1]->add_child($initialized_components{$component_id})
          if $params{component_current_parent}[-1];

      push @{$params{component_current_parent}}, $initialized_components{$component_id};
      $params{node}->attr('data-pure-component-id'=>$component_id);

      push @{$params{directives}}, "^*[data-pure-component-id=$component_id]", sub {
        my ($t, $dom, $data) = @_;
        my $comp = $initialized_components{$component_id} || return;
        $t->encoded_string($comp->apply($dom, $data));
      };
      $params{cnt}++;
      %params = $self->$orig(%params);
      pop @{$params{component_current_parent}} if defined $params{component_current_parent};
      return %params;
    } else {
      return $self->$orig(%params)
    }
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

  extends 'Template::Pure::Component';

  sub template { q[<input></input>] }

  sub directives {
    'input' => 'self.inner_dom',
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
        <pure-input />
      </pure-form>

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

#warn $string;

use Devel::Dwarn;
my %a=$pure->initialized_components;
#Dwarn( $a{'input-3'}->parent->children );


done_testing;
