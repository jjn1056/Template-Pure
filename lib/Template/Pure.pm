use strict;
use warnings;

package Template::Pure;

our $VERSION = '0.001';

use DOM::Tiny;
use Scalar::Util;
use Template::Pure::Utils;
use Template::Pure::Filters;
use Template::Pure::DataContext;
use Template::Pure::DataProxy;
use Template::Pure::EncodedString;
use Template::Pure::Iterator;

sub new {
  my ($proto, %args) = @_;
  my $class = ref($proto) || $proto;
  return bless +{
    filters => $args{filters} || +{},
    dom => DOM::Tiny->new($args{template}),
    directives => $args{directives},
  }, $class;
}

sub render {
  my ($self, $data_proto, $extra_directives) = @_;
  return $self->process_dom($data_proto, $extra_directives)->to_string;
}

sub process_dom {
  my ($self, $data_proto, $extra_directives) = @_;
  return $self->_process_dom_recursive(
    $data_proto,
    $self->{dom},
    @{$self->{directives}},
    @{$extra_directives||[]},
  );
}

sub default_filters { Template::Pure::Filters->all }
sub parse_match_spec { Template::Pure::Utils::parse_match_spec($_[1]) }
sub parse_data_spec { Template::Pure::Utils::parse_data_spec($_[1]) }
sub parse_data_template { Template::Pure::Utils::parse_data_template($_[1]) }
sub parse_itr_spec { Template::Pure::Utils::parse_itr_spec($_[1]) } 
sub escape_html { Template::Pure::Utils::escape_html($_[1]) }
sub encoded_string { Template::Pure::EncodedString->new($_[1]) }

sub data_at_path {
  my ($self, $data, $path) = @_;
  my %data_spec = $self->parse_data_spec($path);
  return $self->_value_from_data($data, %data_spec);
}

sub at_or_die {
  my ($self, $dom, $css) = @_;
  my $new = $dom->at($css);
  die "$css is not a matching path" unless defined $new;
  return $new;
}

sub _process_dom_recursive {
  my ($self, $data_proto, $dom, @directives) = @_;

  $self->{root_data} = $data_proto unless exists $self->{root_data};

  my $data =  Template::Pure::DataContext->new($data_proto, $self->{root_data});

  ($data, @directives) = $self->_process_directive_instructions($dom, $data, @directives);

  while(@directives) {
    my %match_spec = $self->parse_match_spec (shift @directives);
    my $action_proto = shift @directives;

    $dom = $dom->root if $match_spec{absolute};

    if($match_spec{mode} eq 'filter') {
      $self->_process_dom_filter($dom, $data, $match_spec{css}, $action_proto);
    } elsif((ref($action_proto)||'') eq 'HASH') {
      # Could be data remap or iterator
      $self->_process_sub_data($dom, $data, \%match_spec, %{$action_proto});
    } elsif((ref($action_proto)||'') eq 'ARRAY') {
      $self->process_sub_directives($dom, $data->value, $match_spec{css}, @{$action_proto});
    } else {
      my $value = $self->_value_from_action_proto($dom, $data, $action_proto, %match_spec);
      $self->_process_match_spec($dom, $value, %match_spec);
    }
  }

  return $dom;
}

sub _value_from_action_proto {
  my ($self, $dom, $data, $action_proto, %match_spec) = @_;
  if(ref \$action_proto eq 'SCALAR') {
    return $self->_value_from_scalar_action($data, $action_proto);
  } elsif((ref($action_proto)||'') eq 'SCALAR') {
    return $self->_value_from_dom($dom, $$action_proto);
  } elsif((ref($action_proto)||'') eq 'CODE') {
    return $action_proto->($self, $dom, $data);
  } elsif(Scalar::Util::blessed($action_proto) && $action_proto->isa(ref $self)) {
    return $self->_process_template_obj($dom, $data, $action_proto, %match_spec);
  } else {
    die "I encountered an action I don't know what to do with: $action_proto";
  }
}

sub _value_from_scalar_action {
  my ($self, $data, $action_proto) = @_;

  ## If a $action_proto contains a ={ with no | first OR it contains a ={ and no |
  ## That means it is a string with placeholders

  my $first_pipe = index($action_proto, '|');
  my $first_open = index($action_proto, '={');
  
  if(
    (
      ($first_open >= 0) &&
      ($first_open < $first_pipe)
    ) || (
      ($first_open >= 0) &&
      ($first_pipe == -1)
    )
  ) {
    my @parts = map { 
      ref $_ ? $self->_value_from_data($data, %$_) : $_; 
    } $self->parse_data_template($action_proto);
    return join('', @parts);
  } else {
    my %data_spec = $self->parse_data_spec($action_proto);
    return $self->_value_from_data($data, %data_spec);
  }
}

sub _process_template_obj {
  my ($self, $dom, $data, $template, %match_spec) = @_;
  my $content = $self->_value_from_dom($dom, \%match_spec);
  my $new_data = Template::Pure::DataProxy->new(
    $data->value,
    content => $self->encoded_string($content));
      
  return $self->encoded_string($template->render($new_data));
}

sub _process_directive_instructions {
  my ($self, $dom, $data, @directives) = @_;
  if( (ref($directives[0])||'') eq 'HASH') {
    my %map = %{shift(@directives)};
    my %new_data;
    foreach my $key (keys %map) {
      $new_data{$key} = $self->_value_from_action_proto($dom, $data, $map{$key});
    }
    $data = Template::Pure::DataContext->new(\%new_data);
  }
  return ($data, @directives);
}

sub _process_sub_data {
  my ($self, $dom, $data, $match_spec, %action) = @_;

  # I don't know what it means to match repeat on attribes or append/prepent
  # right now, so just doing match on the CSS and welcome specifications for
  # this behavior.

  my $css = $match_spec->{css};
  
  # Pull out any sort or filters
  my $sort_cb = exists $action{order_by} ? delete $action{order_by} : undef;
  my $filter_cb = exists $action{filter} ? delete $action{filter} : undef;
  my $display_fields = exists $action{display_fields} ? delete $action{display_fields} : undef;
  my $following_directives = exists $action{directives} ? delete $action{directives} : undef;

  my ($sub_data_proto, $sub_data_action) = %action;

  ## TODO: Allow fro $sub_data_proto to be a template object
  die "Action for '$sub_data_proto' must be an arrayref of new directives"
    unless ref $sub_data_action eq 'ARRAY';

  if(index($sub_data_proto,'<-') > 0) {
    my ($new_key, $itr_data_spec) = $self->parse_itr_spec($sub_data_proto);
    my $itr_data_proto = $self->_value_from_data($data, %$itr_data_spec);

    ## For now if the found value is undef, we second it along ti be trimmed
    ## this behavior might be tweaked as examples of usage arise, also for now
    ## we just pass through an empty iterator instead of considering it undef
    ## ie [] is not considered like undef for now...

    return $self->_process_match_spec($dom, $itr_data_proto, %$match_spec)
      if $self->_value_is_undef($itr_data_proto);

    my %options;
    if($display_fields) {
      $options{display_fields} = $display_fields;
    }

    my $iterator = Template::Pure::Iterator->from_proto($itr_data_proto, $sort_cb, $filter_cb, \%options);
    
    if($css eq '.') {
      $self->_process_iterator($dom, $new_key, $iterator, @{$sub_data_action});
    } else {
      my $collection = $dom->find($css);
      $collection->each(sub {
        $self->_process_iterator($_, $new_key, $iterator, @{$sub_data_action});
      });
    }
  } else {
    my %sub_data_spec = $self->parse_data_spec($sub_data_proto);  
    my $value = $self->_value_from_data($data, %sub_data_spec);

    ## If the value is undefined, we dont' continue... should we remove all this...?

    $self->process_sub_directives($dom, $value, $css, @{$sub_data_action});
  }

  ## Todo... not sure if this is right or useful
  if($following_directives) {
    $self->process_sub_directives($dom, $data, $css, @{$following_directives});
  }
}

sub _process_iterator {
  my ($self, $dom, $key, $iterator, @actions) = @_; 
  my $new_dom = DOM::Tiny->new($dom);
  while(my $datum = $iterator->next) {
    my $new_data = +{
      $key => $datum, 
      i => $iterator,
    };
    $self->_process_dom_recursive($new_data, $new_dom->descendant_nodes->[0], @actions);
    $dom->replace($new_dom); #Not sure why this is actually working....
    #$iterator->is_first ? $dom->replace($new_dom) : $dom->append($new_dom);
  }
}

sub process_sub_directives {
  my ($self, $dom, $data, $css, @directives) = @_;
  if($css eq '.') {
    $self->_process_dom_recursive($data, $dom, @directives);
  } else {
    my $collection = $dom->find($css);
    $collection->each(sub {
        $self->_process_dom_recursive($data, $_, @directives);
    });
  }
}

sub _value_from_dom {
  my $self = shift;
  my $dom = shift;
  my %match_spec = ref $_[0] ? %{$_[0]} : $self->parse_match_spec($_[0]);

  $dom = $dom->root if $match_spec{absolute};

  ## TODO, perhaps this could do a find instead of at and return
  ## a collection, which populates an iterator if requested?

  if($match_spec{target} eq 'content') {
    return $self->at_or_die($dom, $match_spec{css})->content;
  } elsif($match_spec{target} eq 'node') {
    ## When we want a full node, with HTML tags, we encode the string
    ## since I presume they want a copy not escaped.  T 'think' this is
    ## the commonly desired thing and you can always apply and escape_html filter
    ## yourself when you don't want it.
    return $self->encoded_string($self->at_or_die($dom, $match_spec{css})->to_string);
  } elsif(my $attr = ${$match_spec{target}}) {
    return $self->at_or_die($dom, $match_spec{css})->attr($attr);
  }
}

sub _value_from_data {
  my ($self, $data, %data_spec) = @_;
  my $value = $data->at(%data_spec)->value;
  foreach my $filter (@{$data_spec{filters}}) {
    $value = $self->_apply_data_filter($value, $data, $filter);
  }
  return $value;
}

sub _apply_data_filter {
  my ($self, $value, $data, $filter) = @_;
  my ($name, @args) = @$filter;
  @args = map { ref $_ ? $self->_value_from_data($data, %$_) : $_ } @args;
  return $self->filter($name, $value, @args);
}

sub _process_dom_filter {
  my ($self, $dom, $data, $css, $cb) = @_;
  if($css eq '.') {
    $cb->($self, $dom, $data);
  } else {
    my $collection = $dom->find($css);
    $collection->each(sub {
      $cb->($self, $dom, $data);
    });
  }
}

sub _process_match_spec {
  my ($self, $dom, $value, %match_spec) = @_;
  if($match_spec{css} eq '.') {
    $self->_process_mode($dom, $value, %match_spec);
  } else {
    my $collection = $dom->find($match_spec{css});
    $collection->each(sub {
      $self->_process_mode($_, $value, %match_spec);
    });
  }
}

sub _value_is_undef {
  my ($self, $value) = @_;
  return 1 if !defined($value);
  return 1 if Scalar::Util::blessed($value) && $value->isa('Template::Pure::UndefObject');
  return 0;
}


sub _process_mode {
  my ($self, $dom, $value, %match_spec) = @_;

  my $mode = $match_spec{mode};
  my $target = $match_spec{target};
  my $safe_value = $self->escape_html($value);

  ## This behavior may be tweaked in the future.
  return $dom->remove if $self->_value_is_undef($safe_value);

  if($mode eq 'replace') {
    if($target eq 'content') {
      $dom->content($safe_value) unless $self->_value_is_undef($safe_value);
    } elsif($target eq 'node') {
      $dom->replace($safe_value);
    } elsif(my $attr = $$target) {
      $dom->attr($attr=>$safe_value);
    } else {
      die "Don't understand target of $target";
    }
  } elsif($mode eq 'append') {
    if($target eq 'content') {
      $dom->append_content($safe_value);
    } elsif($target eq 'node') {
      $dom->append($safe_value);
    } elsif(my $attr = $$target) {
      my $current_attr = $dom->attr($attr)||'';
      $dom->attr($attr=>"$current_attr$safe_value" );
    } else {
      die "Don't understand target of $target";
    }
  } elsif($mode eq 'prepend') {
    if($target eq 'content') {
      $dom->prepend_content($safe_value);
    } elsif($target eq 'node') {
      $dom->prepend($safe_value);
    } elsif(my $attr = $$target) {
      my $current_attr = $dom->attr($attr)||'';
      $dom->attr($attr=> "$safe_value$current_attr" );
    } else {
      die "Don't understand target of $target";
    }
  } else {
    die "Not sure how to handle mode '$mode'";
  }
}

sub filter {
  my ($self, $name, $data, @args) = @_;
  my %filters = (
    $self->default_filters,
    %{$self->{filters}}
  );
  
  my $filter = $filters{$name} ||
    die "Filter $name does not exist";
    
  return $filter->($self, $data, @args);
}

1;

=head1 NAME

Template::Pure - Perlish Port of pure.js

=head1 SYNOPSIS

    use Template::Pure;

    my $html = q[
      <html>
        <head>
          <title>Page Title</title>
        </head>
        <body>
          <section id="article">
            <h1>Header</h1>
            <div>Story</div>
          </section>
          <ul id="friendlist">
            <li>Friends</li>
          </ul>
        </body>
      </html>
    ];

    my $pure = Template::Pure->new(
      template=>$html,
      directives=> [
        'head title' => 'meta.title',
        '#article' => [
          'h1' => 'header',
          'div' => 'content',
        ],
        'ul li' => {
          'friend<-user.friends' => [
            '.' => '={friend}, #={i.index}',
          ],
        },
      ],    
    );

    my $data = +{
      meta => {
        title => 'Travel Poetry',
        created_on => '1/1/2000',
      },
      header => 'Fire',
      content => q[
        Are you doomed to discover that you never recovered from the narcoleptic
        country in which you once stood? Where the fire's always burning, but
        there's never enough wood?
      ],
      user => {
        name => 'jnap',
        friends => [qw/jack jane joe/],
      },
    };

    print $pure->render($data);

Results in:

    <html>
      <head>
        <title>Travel Poetry</title>
      </head>
      <body>
        <section id="article">
          <h1>Fire</h1>
          <div>
            Are you doomed to discover that you never recovered from the narcoleptic
            country in which you once stood? Where the fire&#39;s always burning, but
            there&#39;s never enough wood?
          </div>
        </section>
        <ul id="friendlist">
          <li>jack, #1</li>
          <li>jane, #2</li>
          <li>joe, #3</li>
        </ul>
      </body>
    </html>

=head1 DESCRIPTION

B<NOTE> WARNING: Early access module. Although we have a lot of test cases and this is the
third redo of the code I've not well tested certain features (such as using an object as
a data context) and other parts such as the way we handle undefined values (or empty
iterators) are still 'first draft'.  Code currently is entirely unoptimized.  Additionally the
documenation could use another detailed review, and we'd benefit from some 'cookbook' style docs.
Nevertheless its all working well enough that I'd like to publish it so I can start using it 
more widely and hopefully some of you will like what you see and be inspired to try and help
close the gaps.

L<Template::Pure> HTML/XML Templating system, inspired by pure.js L<http://beebole.com/pure/>, with
some additions and modifications to make it more Perlish and to be more suitable
as a server side templating framework for larger scale needs instead of single page
web applications.

The core concept is you have your templates in pure HTML and create CSS style
matches to run transforms on the HTML to populate data into the template.  This allows you
to have very clean, truely logicless templates.  This approach can be useful when the HTML designers
know little more than HTML and related technologies.  It  helps promote separation of concerns
between your UI developers and your server side developers.  Over the long term the separate
and possibilities for code reuse can lead to an easier to maintain system.

The main downside is that it can place more work on the server side developers, who have to
write the directives unless your UI developers are able and willing to learn the minimal Perl
required for that job.  Also since the CSS matching directives can be based on the document
structure, it can lead to onerous tight binding between yout document structure and the layout/display
logic.  For example due to some limitations in the DOM parser, you might have to add some extra markup
just so you have a place to match, when you have complex and deeply nested data.

Additionally many UI  designers already are familiar with some basic templating systems and 
might really prefer to use that so that they can maintain more autonomy and avoid the additional
learning curve that L<Template::Pure> will requires (most people seem to find its a bit more
effort to learn off the top compared to more simple systems like Mustache or even L<Template::Toolkit>.

Although inspired by pure.js L<http://beebole.com/pure/> this module attempts to help mitigate some
of the listed possible downsides with additional features that are a superset of the original 
pure.js specification. For example you may include templates inside of templates as includes or even
overlays that provide much of the same benefit that template inheritance offers in many other
popular template frameworks.  These additional features are intended to make it more suitable as a general
purpose server side templating system.

=head1 CREATING TEMPLATE OBJECTS

The first step is to create a L<Template::Pure> object:

    my $pure = Template::Pure->new(
      template=>$html,
      directives=> \@directives);

L<Template::Pure> has two required parameters:

=over 4

=item template

This is a string that is an HTML template that can be parsed by L<DOM::Tiny>

=item directives

An arrayref of directives, which are commands used to transform the template when
rendering against data.  For more on directives, see L</DIRECTIVES>

=back

L<Template::Pure> has a third optional parameter, 'filters', which is a hashref of
user created filters.  For more see L<Template::Pure::Filters> and L</FILTERS>.

Once you have a created object, you may call the following methods:

=over 4

=item render ($data, ?\@extra_directives?)

Render a template with the given '$data', which may be a hashref or an object with
fields that match data paths defined in the directions section (see L</DIRECTIVES>)

Returns a string.  You may pass in an arrayref of extra directives, which are executed
just like directives defined at instantiation time (although future versions of this
distribution may offer optimizations to directives known at create time).  These optional
added directives are executed after the directives defined at create time.

Since we often traverse the $data structure as part of rendering a template, we usually call
the current path the 'data context'.  We always track the base or root context and you can
always return to it, as you will later see in the L</DIRECTIVES> section.

=item process_dom ($data, ?\@extra_directives?)

Works just like 'render', except we return a L<DOM::Tiny> object instead of a string directly.
Useful if you wish to retrieve the L<DOM::Tiny> object for advanced, custom tranformations.

=item data_at_path ($data, $path)

Given a $data object, returns the value at the defined $path.  Useful in your coderef actions
(see below) when you wish to grab data from the current data context but wish to avoid
using $data implimentation specific lookup.

=item escape_html ($string)

Given a string, returns a version of it that has been properly HTML escaped.  Since we do
such escaping automatically for most directives you won't need it a lot, but could be useful
in a coderef action.  Can also be called as a filter (see L</FILTERS>).

=item encoded_string ($string)

As mentioned we automatically escape values to help protect you against HTML injection style
attacked, but there might be cases when you don't wish this protection.  Can also be called
as a filter (see L</FILTERS>).

=back

There are other methods in the code but please consider all that stuff part of my 'black box'
and only reach into it if you are willing to suffer possible breakage on version changes.

=head1 DIRECTIVES

Directives are instructions you prepare against a template, upon which later we render
data against.  Directives are ordered and are excuted in the order defined.  The general
form of a directive is C<CSS Match> => C<Action>, where action can be a path to fetch data
from, more directives, a coderef, etc.  The main idea is that the CSS matches
a node in the HTML template, and an 'action' is performed on that node.  The following actions are allowed
against a match specification:

=head2 Scalar - Replace the value indicated by the match.

    my $html = qq[
      <div>
        Hello <span id='name'>John Doe</span>!
      </div>
    ];

    my $pure = Template::Pure->new(
      template => $html,
      directives => [
        '#name' => 'fullname',
      ]);

    my %data = (
      fullname => 'H.P Lovecraft');

    print $pure->render(\%data);

Results in:

    <div>
      Hello <span id='name'>H.P Lovecraft</span>!
    </div>

In this simple case the value of the CSS match '#name' is replaced by the value 'fullname'
indicated at the current data context (as you can see the starting context is always the
root, or top level data object.)

If instead of a hashref the rendered data context is an object, we look for a method
matching the name of the indicated path.  If there is no matching method or key, we generate
an exception.

If there is a key matching the requested data path as indicated by the directive, but the associated
value is undef, then the matching node (tag included) is removed. If there is no matching key,
this raises an error.

B<NOTE>: Remember that you can use dot notation in your action value to indicate a path on the
current data context, for example:

    my %data = (
      identity => {
        first_name => 'Howard',
        last_name => 'Lovecraft',
      });

    my $pure = Template::Pure->new(
      template => $html,
      directives => [ '#last_name' => 'identity.last_name']
    );

In this case the value of the node indicated by '#last_name' will be set to 'Lovecraft'.

=head2 ScalarRef - Set the value to the results of a match

There may be times when you want to set the value of something to an existing
value in the current template:

    my $html = qq[
      <html>
        <head>
          <title>Welcome Page</title>
        </head>
        <body>
          <h1>Page Title</h1>
        </body>
      </html>
    ];

    my $pure = Template::Pure->new(
      template = $html,
      directives => [
        'h1#title' => \'/title',
      ]);

    print $pure->render({});

Results in:

    <html>
      <head>
        <title>Welcome Page</title>
      </head>
      <body>
        <h1>Welcome Page</h1>
      </body>
    </html>

B<NOTE> Since directives are processed in order, this means that you can
reference the rendered value of a previous directive via this alias.

B<NOTE> The match runs against the current selected node, as defined by the last
successful match.  If you need to match a value from the root of the DOM tree you
can use the special '/' syntax on your CSS match, as shown in the above example,
or:

    directives => [
      'h1#title' => \'/title',
    ]);


=head2 Coderef - Programmatically replace the value indicated

    my $html = qq[
      <div>
        Hello <span id='name'>John Doe</span>!
      </div>
    ];

    my $pure = Template::Pure->new(
      template => $html,
      directives => [
        '#name' => sub {
          my ($instance, $dom, $data) = @_;
          return $data->{id}{first_name} .' '. $data->{id}{first_name}; 
        },
      ]
    );

    my %data = (
      id => {
        first_name => 'Howard',
        last_name => 'Lovecraft',
      });

    print $pure->render(\%data);


Results in:

    <div>
      Hello <span id='name'>Howard Lovecraft</span>!
    </div>

For cases where the display logic is complex, you may use an anonymous subroutine to
provide the matched value.  This anonymous subroutine receives the following three
arguments:

    $instance: The template instance
    $dom: The DOM Node at the current match (as a L<DOM::Tiny> object).
    $data: Data reference at the current context.

Your just need to return the value desired which will substitute for the matched node's
current value.

B<NOTE>: It might be a good idea to try and maintain as much implementation independence
from you $data model as possible.  That way if later you change your $data from a hashref
to an instance of an object you won't break your code.  One way to help achieve this is
to use L<Template::Pure>'s data lookup helper methods (which support dot notation and more
as described below.  For example consider re-writing the above example like this:

    my $pure = Template::Pure->new(
      template => $html,
      directives => [
        '#name' => sub {
          my ($instance, $dom, $data) = @_;
          return $instance->data_at_path($data, 'id.first_name') .' '. 
            $instance->data_at_path($data, 'id.last_name') ; 
        },
      ]
    );

=head2 Arrayref - Run directives under a new DOM root

Somtimes its handy to group a set of directives under a given node.  For example:

    my $html = qq[
      <dl id='contact'>
        <dt>Phone</dt>
        <dd class='phone'>(xxx) xxx-xxxx</dd>
        <dt>Email</dt>
        <dd class='email'>aaa@email.com</dd>
      </dl>
    ];

    my $pure = Template::Pure->new(
      template = $html,
      directives => [
        '#contact' => [
          '.phone' => 'contact.phone',
          '.email' => 'contact.email',
      ],
    );

    my %data = (
      contact => {
        phone => '(212) 387-9509',
        email => 'jjnapiork@cpan.org',
      }
    );

    print $pure->render(\%data);

Results in:

    <dl id='contact'>
      <dt>Phone</dt>
      <dd class='phone'>(212) 387-9509</dd>
      <dt>Email</dt>
      <dd class='email'>jjnapiork@cpan.org'</dd>
    </dl>

For this simple case you could have made it more simple and avoided the nested directives, but
in a complex template with a lot of organization you might find this leads to more readable and
concise directives. It can also promote reusability.

=head2 Hashref - Move the root of the Data Context

Just like it may be valuable to move the root DOM context to an inner node, sometimes you'd
like to move the root of the current Data context to an inner path point.  This can result in cleaner
templates with less repeated syntax, as well as promote reusability. In order to do this you
use a Hashref whose key is the path under the data context you wish to move to and who's value
is an Arrayref of new directives.  These new directives can be any type of directive as already
shown or later documented.  

    my $html = qq[
      <dl id='contact'>
        <dt>Phone</dt>
        <dd class='phone'>(xxx) xxx-xxxx</dd>
        <dt>Email</dt>
        <dd class='email'>aaa@email.com</dd>
      </dl>
    ];

    my $pure = Template::Pure->new(
      template => $html,
      directives => [
        '#contact' => {
          'contact' => [
          '.phone' => 'phone',
          '.email' => 'email',
          ],
        },
      ]
    );

    my %data = (
      contact => {
        phone => '(212) 387-9509',
        email => 'jjnapiork@cpan.org',
      }
    );

    print $pure->render(\%data);

Results in:

    <dl id='contact'>
      <dt>Phone</dt>
      <dd class='phone'>(212) 387-9509</dd>
      <dt>Email</dt>
      <dd class='email'>jjnapiork@cpan.org'</dd>
    </dl>

=head2 Hashref - Create a Loop

Besides moving the current data context, setting the value of a match spec key to a
hashref can be used to perform loops over a node, such as when you wish to create
a list:

    my $html = qq[
      <ol>
        <li class='name'>
          <span class='first-name'>John</span>
          <span class='last-name'>Doe</span>
        </li>
      </ol>
    ];

    my $pure = Template::Pure->new(
      template => $html,
      directives => [
        '#name' => {
          'name<-names' => [
            '.first-name' => 'name.first',
            '.last-name' => 'name.last',
          ],
        },
      ]
    );

    my %data = (
      names => [
        {first => 'Mary', last => 'Jane'},
        {first => 'Jared', last => 'Prex'},
        {first => 'Lisa', last => 'Dig'},
      ]
    );

    print $pure->render(\%data);

Results in:

    <ol id='names'>
      <li class='name'>
        <span class='first-name'>Mary</span>
        <span class='last-name'>Jane</span>
      </li>
      <li class='name'>
        <span class='first-name'>Jared</span>
        <span class='last-name'>Prex</span>
      </li>
      <li class='name'>
        <span class='first-name'>Lisa</span>
        <span class='last-name'>Dig</span>
      </li>
    </ol>

The indicated data path must be either an ArrayRef, a Hashref, or an object that provides
an iterator interface (see below).

For each item in the array we render the selected node against that data and
add it to parent node.  So the originally selected node is completely replaced by a
collection on new nodes based on the data.  Basically just think you are repeating over the
node value for as many times as there is items of data.

In the case the referenced data is explicitly set to undefined, the full node is
removed (the matched node, not just the value).

=head3 Special value injected into a loop

When you create a loop we automatically add a special data key called 'i' which is an object
that contains meta data on the current state of the loop. Fields that can be referenced are:

=over 4

=item current_value

An alias to the current value of the iterator.

=item index

The current index of the iterator (starting from 1.. or from the first key in a hashref or fields
interator).

=item max_index

The last index item, either number or field based.

=item count

The total number of items in the iterator (as a number, starting from 1).

=item is_first

Is this the first item in the loop?

=item is_last

Is this the last item in the loop?

=item is_even

Is this item 'even' in regards to its position (starting with position 2 (the first position, or also
known as index '1') being even).

=item is_odd

Is this item 'even' in regards to its position (starting with position 1 (the first position, or also
known as index '0') being odd).

=back

=head3 Looping over a Hashref

You may loop over a hashref as in the following example:

    my $html = qq[
      <dl id='dlist'>
        <section>
          <dt>property</dt>
          <dd>value</dd>
        </section>
      </dl>];

    my $pure = Template::Pure->new(
      template => $html,
      directives => [
        'dl#dlist section' => {
          'property<-author' => [
            'dt' => 'i.index',
            'dd' => 'property',
          ],
        },
      ]
    );

    my %data = (
      author => {
        first_name => 'John',
        last_name => 'Napiorkowski',
        email => 'jjn1056@yahoo.com',
      },
    );

    print $pure->render(\%data);

Results in:

    <dl id="dlist">
      <section>
        <dt>first_name</dt>
        <dd>John</dd>
      </section>
      <section>
        <dt>last_name</dt>
        <dd>Napiorkowski</dd>
      </section>
      <section>
        <dt>email</dt>
        <dd>jjn1056@yahoo.com</dd>
      </section>
    </dl>

B<NOTE> This is a good example of a current limitation in the CSS Match Specification that
requires adding a 'section' tag as a fudge to give the look something to target.  Future
versions of this distribution may offer additional match syntax to get around this problem.

B<NOTE> Notice the usage of the special data path 'i.index' which for a hashref or fields
type loop contains the field or hashref key name.

B<NOTE> Please remember that in Perl Hashrefs are not ordered.  If you wish to order your
Hashref based loop please see L</Sorting and filtering a Loop> below.

=head3 Iterating over an Object

If the value indicated by the required path is an object, we need that object to provide
an interface indicating if we should iterate like an ArrayRef (for example a L<DBIx::Class::ResultSet>
which is a collection of database rows) or like a HashRef (for example a L<DBIx::Class>
result object which is one row in the returned database query consisting of field keys
and associated values).

=head4 Objects that iterate like a Hashref

The object should provide a method called 'display_fields' (which can be overridden with
the key 'display_fields_handler', see below) which should return a list of methods that are used
as 'keys' to provide values for the iterator.  Each method return represents one item
in the loop.

=head4 Objects that iterate like an ArrayRef

Your object should defined the follow methods:

=over 4

=item next

Returns the next item in the iterator or undef if there are no more items

=item count

The number of items in the iterator (counting from 1 for one item)

=item reset

Reset the iterator to the starting item.

=item all 

Returns all the items in the iterator

=back

=head3 Sorting and filtering a Loop

You may provide a custom anonymous subroutine to provide a display
specific order to your loop.  For simple values such as Arrayrefs
and hashrefs this is simple:

    my $html = qq[
      <ol id='names'>
        <li class='name'>
          <span class='first-name'>John</span>
          <span class='last-name'>Doe</span>
        </li>
      </ol>
    ];

    my $pure = Template::Pure->new(
      template = $html,
      directives => [
        '#name' => {
          'name<-names' => [
            '.first-name' => 'name.first',
            '.last-name' => 'name.last',
          ],
          'order_by' => sub {
            my ($hashref, $a, $b) = @_;
            return $a->{last} cmp $b->{last};
          },
        },
      ]
    );

    my %data = (
      names => [
        {first => 'Mary', last => 'Jane'},
        {first => 'Jared', last => 'Prex'},
        {first => 'Lisa', last => 'Dig'},
      ]
    );

    print $pure->render(\%data);

Results in:

    <ol id='names'>
      <li class='name'>
        <span class='first-name'>Lisa</span>
        <span class='last-name'>Dig</span>
      </li>
      <li class='name'>
        <span class='first-name'>Mary</span>
        <span class='last-name'>Jane</span>
      </li>
      <li class='name'>
        <span class='first-name'>Jared</span>
        <span class='last-name'>Prex</span>
      </li>
    </ol>

So you have a key 'order_by' at the same level as the loop action declaration
which is an anonynous subroutine that takes three arguments, the first being
a reference to the data you are sorting (an arrayref or hashref)
followed by the $a and $b items to be compared for example as in:

    my @display = sort { $a->{last} cmp $b->{last} } @list;

If your iterator is over an object the interface is slightly more complex since
we allow for the object to provide a sort method based on its internal needs.
For example if you have a L<DBIx::Class::Resultset> as your iterator, you may
wish to order your display at the database level:

    'sort' => sub {
      my ($object) = @_;
      return $object->order_by_last_name;
    },

We recommend avoiding implimentation specific details when possible (for example
in L<DBIx::Class> use a custom resultset method, not a ->search query.).

=head3 Perform a 'filter' on your loop items

You may wish for the purposes of display to skip items in your loop.  Similar to
'order_by', you may create a 'grep' key that returns either true or false to determine
if an item in the loop is allowed (works like the 'grep' function).

    # Only show items where the value is greater than 10.
    'filter' => sub {
      my ($template, $item) = @_;
      return $item > 10; 
    },

Just like with 'order_by', if your iterator is over an object, you recieve that
object as the argument and are expected to return a new iterator that is properly
filtered:

    'grep' => sub {
      my ($template, $iterator) = @_;
      return $iterator->only_over_10;
    },

=head3 Generating display_fields

When you are iterating over an object that is like a Hashref, you need
to inform us of how to get the list of field names which should be the
names of methods on your object who's value you wish to display.  By default
we look for a method called 'display fields' but you can customize this
in one of two ways.  You can set a key 'display_fields' to be the name of
an alternative method:

    directives => [
      '#meta' => {
        'field<-info' => [
            '.name' => 'field.key',
            '.value' => 'field.value',
          ],
          'display_fields' => 'columns',
        },
      ]

=head2 Object - Set the match value to another Pure Template

    my $section_html = qq[
      <div>
        <h2>Example Section Title</h2>
        <p>Example Content</p>
      </div>
    ];

    my $pure_section = Template::Pure->new(
      template = $section_html,
      directives => [
        'h2' => 'title',
        'p' => 'story'
      ]);

    my $html = qq[
      <div class="story">Example Content</div>
    ];

    my $pure = Template::Pure->new(
      template = $html,
      directives => [
        'div.story' => $pure_section,
      ]);

    my %data = (
      title => 'The Supernatural in Literature',
      story => $article_text,
    );

    print $pure->render(\%data);

Results in:

    <div class="story">
      <div>
        <h2>The Supernatural in Literature</h2>
        <p>$article_text</p>
      </div>
    </div>

When the action is an object it must be an object that conformation
to the interface and behavior of a L<Template::Pure> object.  For the
most part this means it must be an object that does a method 'render' that
takes the current data context refernce and returns an HTML string suitable
to become that value of the matched node.

When encountering such an object we pass the current data context, but we
add one additional field called 'content' which is the value of the matched
node.  You can use this so that you can 'wrap' nodes with a template (similar
to the L<Template> WRAPPER directive).

    my $wrapper_html = qq[
      <p class="headline">To Be Wrapped</p>
    ];

    my $wrapper = Template::Pure->new(
      template = $wrapper_html,
      directives => [
        'p.headline' => 'content',
      ]);

    my $html = qq[
      <div>This is a test of the emergency broadcasting
      network... This is only a test</div>
    ];

    my $wrapper = Template::Pure->new(
      template = $html,
      directives => [
        'div' => $wrapper,
      ]);

Results in:

    <div>
      <p class="headline">This is a test of the emergency broadcasting
      network... This is only a test</p>
    </div>

Lastly you can mimic a type of inheritance using data mapping and
node aliasing:

   my $master_html = q[
      <html>
        <head>
          <title>Example Title</title>
          <link rel="stylesheet" href="/css/pure-min.css"/>
            <link rel="stylesheet" href="/css/grids-responsive-min.css"/>
              <link rel="stylesheet" href="/css/common.css"/>
          <script src="/js/3rd-party/angular.min.js"></script>
            <script src="/js/3rd-party/angular.resource.min.js"></script>
        </head>
        <body>
          <section id="content">...</section>
          <p id="foot">Here's the footer</p>
        </body>
      </html>
    ];

    my $master = Template::Pure->new(
      template=>$master_html,
      directives=> [
        'title' => 'title',
        '^title+' => 'scripts',
        'body section#content' => 'content',
      ]);

    my $page_html = q[
      <html>
        <head>
          <title>The Real Page</title>
          <script>
          function foo(bar) {
            return baz;
          }
          </script>
        </head>
        <body>
          You are doomed to discover that you never
          recovered from the narcolyptic country in
          which you once stood; where the fire's always
          burning but there's never enough wood.
        </body>
      </html>
    ];

    my $page = Template::Pure->new(
      template=>$page_html,
      directives=> [
        'title' => 'meta.title',
        'html' => [
          {
            title => \'title',
            scripts => \'^head script',
            content => \'body',
          },
          '^.' => $master,
        ]
      ]);

    my $data = +{
      meta => {
        title => 'Inner Stuff',
      },
    };

Results in:

    <html>
      <head>
        <title>Inner Stuff</title><script>
        function foo(bar) {
          return baz;
        }
        </script>
        <link href="/css/pure-min.css" rel="stylesheet">
          <link href="/css/grids-responsive-min.css" rel="stylesheet">
            <link href="/css/common.css" rel="stylesheet">
        <script src="/js/3rd-party/angular.min.js"></script>
          <script src="/js/3rd-party/angular.resource.min.js"></script>
      </head>
      <body>
        <section id="content">
        You are doomed to discover that you never
        recovered from the narcolyptic country in
        which you once stood; where the fire&amp;#39;s always
        burning but there&amp;#39;s never enough wood.
      </section>
        <p id="foot">Here&#39;s the footer</p>
      </body>
    </html>

=head2 Using Dot Notation in Directive Data Mapping

L<Template::Pure> allows you to indicate a path to a point in your
data context using 'dot' notation, similar to many other template
systems such as L<Template>.  In general this offers an abstraction
that smooths over the type of reference your data is (an object, or
a hashref) such as to make it easier to swap the type later on as
needs grow, or for testing:

    directives => [
      'title' => 'meta.title',
      'copyright => 'meta.license_info.copyright_date',
      ...,
    ],

    my %data = (
      meta => {
        title => 'Hello World!',
        license_info => {
          type => 'Artistic',
          copyright_date => 2016,
        },
      },
    );

Basically you use '.' to replace '->' and we figure out if the path
is to a key in a hashref or method on an object for you.

In the case when the value of a path is explictly undefined, the behavior
is to remove the matching node (the full matching node, not just the value).

Trying to resolve a key or method that does not exist returns an error.
However its not uncommon for some types of paths to have optional parts
and in these cases its not strictly and error when the path does not exist.
In this case you may prefix 'optional:' to your path part, which will surpress
an error in the case the requested path does not exist:

    directives => [
      'title' => 'meta.title',
      'copyright => 'meta.license_info.optional:copyright_date',
      ...,
    ],

In this case instead of returning an error we treat the path as though it
returned 'undefined' (which means we trim out the matching node).

In other cases your path might exist, but returns undefined.  This can be an
issue if you have following paths (common case when traversing L<DBIx::Class>
relationships...) and you don't want to throw an exception.  In this case you
may use a 'maybe:' prefix, which returns undefined and treats the entire remaining
path as undefined:

    directives => [
      'title' => 'meta.title',
      'copyright => 'meta.maybe:license_info.copyright_date',
      ...,
    ],

=head2 Remapping Your Data Context

If the first element of your directives (either at the root of the directives
or when you create a new directives list under a given node) is a hashref
we take that as special instructions to remap the current data context to
a different structure.  Useful for increase reuse and decreasing complexity
in some situations:

    my $html = qq[
      <dl id='contact'>
        <dt>Phone</dt>
        <dd class='phone'>(xxx) xxx-xxxx</dd>
        <dt>Email</dt>
        <dd class='email'>aaa@email.com</dd>
      </dl>
    ];

    my $pure = Template::Pure->new(
      template = $html,
      directives => [
        '#contact' => [
          { 
            phone => 'contact.phone',
            email => 'contact.email,
          },  [
          '.phone' => 'phone',
          '.email' => 'email',
          ],
        },
      ]
    );

    my %data = (
      contact => {
        phone => '(212) 387-9509',
        email => 'jjnapiork@cpan.org',
      }
    );

    print $pure->render(\%data);

Results in:

    <dl id='contact'>
      <dt>Phone</dt>
      <dd class='phone'>(212) 387-9509</dd>
      <dt>Email</dt>
      <dd class='email'>jjnapiork@cpan.org'</dd>
    </dl>

=head2 Using Placeholders in your Actions

Sometimes it makes sense to compose your replacement value of several
bits of information.  Although you could do this with lots of extra 'span'
tags, sometimes its much more clear and brief to put it all together.  For
example:

    my $pure = Template::Pure->new(
      template => $html,
      directives => [
        '#content' => 'Hi ={name}, glad to meet you on=#{today}',
      ]
    );

In the case your value does not refer itself to a path, but instead contains
one or more placeholders which are have data paths inside them.  These data
paths can be simple or complex, and even contain filters:

    my $pure = Template::Pure->new(
      template => $html,
      directives => [
        '#content' => 'Hi ={name | uc}, glad to meet you on ={today}',
      ]
    );

For more on filters see L</FILTERS>

=head2 Special indicators in your match.

In General your match specification is a CSS match supported by the
underlying HTML parser.  However the following specials are supported
for needs unique to the needs of templating:

=over 4

=item '.': Select the current node

Used to indicate the current root node.  Useful when you have created a match
with sub directives.

    my $pure = Template::Pure->new(
      template => $html,
      directives => [
        'body' => [
        ]
      ]
    );

=item '/': The root node

Used when you which to select from the root of the template DOM, not the current
selected node.

=item '@': Select an attribute within the current node

Used to update values inside a node:

    my $pure = Template::Pure->new(
      template => $html,
      directives => [
        'h1@class' => 'header_class',
      ],
    );

=item '+': Append or prepend a value

    my $pure = Template::Pure->new(
      template => $html,
      directives => [
        '+h1' => 'title',
        '#footer+' => 'copyright_date',
      ],
    );

The default behavior is for a match to replace the matched node's content.  In some
cases you may wish to preserve the template content and instead either add more
content to the front or back of it.

B<NOTE> Can be combined with '@' to append / prepend to an attribute.

B<NOTE> Special handling when appending or prepending to a class attribute (we add a
space if there is an existing since that is expected).

=item '^': Replace current node completely

Normally we replace, append or prepend to the value of the selected node.  Using the
'^' at the front of your match indicates operation should happen on the entire node,
not just the value.  Can be combined with '+' for append/prepend.

=item '|': Run a filter on the current node

Passed the currently selected node to a code reference.  You can run L<DOM::Tiny>
transforms on the entire selected node.  Nothing should be returned from this 
coderef.

    'body|' => sub {
      my ($template, $dom, $data) = @_;
      $dom->find('p')->each( sub {
        $_->attr('data-pure', 1);
      });
    }

=back 

=head1 FILTERS

You may filter you data via a provided built in display filter:

    my $pure = Template::Pure->new(
      template => $html,
      directives => [
        '#content' => 'data.content | escape_html',
      ]
    );

If a filter takes arguments you may fill those arguments with either literal
values or a 'placeholder' which should point to a path in the current data
context.

    my $pure = Template::Pure->new(
      template => $html,
      directives => [
        '#content' => 'data.content | repeat(#{times}) | escape_html',
      ]
    );

You may add a custom filter when you define your template:

    my $pure = Template::Pure->new(
      filters => {
        custom_filter => sub {
          my ($template, $data, @args) = @_;
          # Do something with the $data, possible using @args
          # to control what that does
          return $data;
        },
      },
    );

An example custom Filter:

    my $pure = Template::Pure->new(
      filters => {
        custom_filter => sub {
          my ($template, $data, @args) = @_;
          # TBD
          # return $data;
        },
      },
    );

In general you can use filters to reduce the need to write your action as a coderef
which should make it easier for you to give the job of writing directives / actions
to non programmers.

See L<Template::Pure::Filters> for all bundled filters.

=head1 IMPORTANT NOTE REGARDING VALID HTML

Please note that L<DOM::Tiny> tends to enforce rule regarding valid HTML5.  For example, you
cannot nest a block level element inside a 'P' element.  This might at time lead to some
surprising results in your output.

=head1 AUTHOR
 
John Napiorkowski L<email:jjnapiork@cpan.org>
  
=head1 SEE ALSO
 
L<DOM::Tiny>, L<Catalyst::View::Template::Pure>.

L<Template::Semantic> is a similar system that uses XPATH instead of a CSS inspired matching
specification.  It has more dependencies (including L<XML::LibXML> and doesn't separate the actual
template data from the directives.  You might find this more simple approach appealing, 
so its worth a look.
 
=head1 COPYRIGHT & LICENSE
 
Copyright 2016, John Napiorkowski L<email:jjnapiork@cpan.org>
 
This library is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.

=cut
