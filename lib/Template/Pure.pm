package Template::Pure;

use Scalar::Util;

sub default_filters {
  my ($class) = @_;
  return (
    uc => sub { uc pop },
    lc => sub { lc pop },
    ltrim => sub { my $s = pop; $s =~ s/^\s+//; return $s },
    rtrim => sub { my $s = pop; $s =~ s/\s+$//; return $s },
    trim => sub { my $s = pop; $s =~ s/^\s+|\s+$//g; return $s },
    escape_html => sub {
      my $s = pop;
      return $s if Scalar::Util::blessed($s) && $s->isa('Template::Pure::EncodedString');
      my %_escape_table = (
        '&' => '&amp;', '>' => '&gt;', '<' => '&lt;', 
        q{"} => '&quot;', q{'} => '&#39;' );
      $s =~ s/([&><"'])/$_escape_table{$1}/ge; 
      return $s;
    },
  );
}

has 


1;


__END__

use warnings;
use strict;

package Template::Pure;

use DOM::Tiny;
use Template::Pure::Iterator;
use Template::Pure::EncodedString;
use Scalar::Util 'blessed';
use Data::Dumper;
use Devel::Dwarn;

sub new {
  my ($proto, %args) = @_;
  my $class = ref($proto) || $proto;
  my %attr = (
    filters => +{$class->default_filters},
    dom => DOM::Tiny->new($args{template}),
    directives => $args{directives});

  return bless \%attr, $class;
}

sub wrapper_data_key { 'content'}

sub wrapper {
  my ($proto, $content_match, $template, $directives) = @_;
  my $class = ref($proto) || $proto;

  return $class->new(
    template => $template,
    directives => [
      @{$directives||[]},
      $content_match => $class->wrapper_data_key,
    ]
  );
}

sub default_filters {
  my ($class) = @_;
  return (
    uc => sub { uc shift },
    lc => sub { lc shift },
    ltrim => sub { my $s = shift; $s =~ s/^\s+//; return $s },
    rtrim => sub { my $s = shift; $s =~ s/\s+$//; return $s },
    trim => sub { my $s = shift; $s =~ s/^\s+|\s+$//g; return $s },
    escape_html => sub {
      my %_escape_table = ( '&' => '&amp;', '>' => '&gt;', '<' => '&lt;', q{"} => '&quot;', q{'} => '&#39;' );
      my $s = shift;
      return $s if blessed $s && $s->isa('Template::Pure::EncodedString');
      $s =~ s/([&><"'])/$_escape_table{$1}/ge; 
      return $s;
    },
  );
}

sub encoded_string { return Template::Pure::EncodedString->new($_[1]) }

sub process_dom {
  my ($self, $data, $opt_directives) = @_;
  my $dom = $self->_render_recursive(
    $data,
    $self->{dom},
    [@{$self->{directives}}, @{$opt_directives||[]}]);
  return $dom;
}
sub render {
  my ($self, $data, $opt_directives) = @_;
  my $string = $self->process_dom($data, $opt_directives)->to_string;
  return $string;
}

sub _parse_match_spec {
  my ($self, $match_spec) = @_;

  my $maybe_wrapper = 0;
  if(my ($wrapper_key) = ($match_spec=~/^\{(.+)\}$/)) {
    $match_spec = $wrapper_key;
    $maybe_wrapper = 1;
  }

  my $maybe_filter = $match_spec=~s/\|$// ? 1:0;
  my $maybe_append = $match_spec=~s/^(\+)// ? 1:0;
  my $maybe_prepend = $match_spec=~s/(\+)$// ? 1:0;
  my ($css, $maybe_attr) = split('@', $match_spec);
  $css = '.' if $maybe_attr && !$css; # not likely to be 0 so this is ok
  return ($css, $maybe_attr, $maybe_prepend, $maybe_append, $maybe_filter, $maybe_wrapper);
}


sub _parse_dataproto {
  my ($self, $tag, $data, $ele) = @_;
  die "Missing tag" unless defined $tag;
  if((ref($tag)||'') eq 'CODE') {
    return $self->_call_codetag($tag, $ele, $data);
  } elsif(my @placeholders = ($tag=~m/(#{.+?})/g)) {
    foreach my $placeholder(@placeholders) {
      my $placeholder_tag = ($placeholder=~/^#{(.+?)}/)[0];
      my $placeholder_value = $self->_parsetag($placeholder_tag, $data);
      $tag=~s/$placeholder/$placeholder_value/g;
    }
    return $tag;
  } else {
    return $self->_parsetag($tag, $data);
  }
}

sub _call_codetag {
  my ($self, $tag, $ele, $data) = @_;
  return $tag->($self, $ele, $data);
}

sub _parsetag {
  my ($self, $tag_proto, $data) = @_;
  my $maybe_optional = $tag_proto=~s/^\?// ? 1:0;
  my ($tag, @filters) = split( /\s*\|\s*/, $tag_proto);
  my ($part, @more) = split(/\.|\//, $tag);

  if($part eq '') {
    $part = shift @more;
    $data = $data->{__root_data__};
  }

  if(  defined(my $value = $self->data_at_path($data, $part, @more)) ) {
    return $self->apply_filters($value, @filters);
  } else {
    die "No value for $tag in: ".Dumper $data
      unless $maybe_optional;
    return bless(\$tag, 'OPTIONAL');
  }
}

sub apply_filters {
  my ($self, $value, @filters) = @_;
  $value = $self->{filters}{$_}->($value) for @filters;
  return $value;
}

sub data_at_path {
  my ($self, $data, $path, @more) = @_;
  return $data unless $path;
  if(blessed $data) {
    return $self->data_at_path($data->$path, @more);
  } else {
    return $self->data_at_path($data->{$path}, @more);
  }
}

sub _render_recursive {
  my ($self, $data, $dom, $directives) = @_;
  my $index = 0;
  while($#{$directives}> $index) {
    my $match = $directives->[$index++];
    my $tag =  $directives->[$index++];
    my ($css, $maybe_attr, $maybe_prepend, $maybe_append, $maybe_filter, $maybe_wrapper) = $self->_parse_match_spec($match);
    if(ref($tag) && ref($tag) eq 'HASH') {
      my $sort_cb = delete $tag->{sort};
      my $filter_cb = delete $tag->{filter};
      my $options = delete $tag->{options};
      my $following_directives = delete $tag->{directives};
      if(my $ele = ($css eq '.' ? $dom : $dom->at($css))) {
        my ($data_spec, $new_directives) = %$tag;
        if($data_spec=~m/\<\-/) {
          my ($new_data_key, $current_key) = split('<-', $data_spec);
          my $iterator_proto = $self->_parse_dataproto($current_key, $data, $ele);
          my $iterator = Template::Pure::Iterator->from_proto($iterator_proto, $sort_cb, $filter_cb, $options);
          while(my $datum = $iterator->next) {
            my $new = DOM::Tiny->new($ele);
            my $new_dom = $self->_render_recursive(
              +{$new_data_key => $datum, i => $iterator, (__root_data__=>$data->{__root_data__}||$data) },
              $new,
              $new_directives);
            $ele->prepend($new_dom);
          }
          $ele->remove($css); #ugly, but can't find a better solution...
        } elsif(my ($merge_key) = ($data_spec=~/^>(.+)<$/)) {
          my $wrapper = $self->_parse_dataproto($merge_key, $data, $ele);
          my %wrapper_data = ();
          foreach my $key(keys %$new_directives) {
            my $wrap_css = $new_directives->{$key};
            if( (ref($wrap_css)||'') eq 'CODE') {
              $wrapper_data{$key} = $self->encoded_string($wrap_css->($self,$ele));
            } elsif(my $wrap_ele = ($wrap_css eq '.' ? $ele : $ele->at($wrap_css))) {
              $wrapper_data{$key} = $self->encoded_string($wrap_ele);
            } else {
              die "no match for '$css' in " .Dumper $ele;
            }
          }
          my $wrapped = $wrapper->process_dom(\%wrapper_data);
          $self->_render_recursive($data, $wrapped, $following_directives) if $following_directives; 
          $ele->replace($wrapped);
        } else {
          # no iterator, just move the context.
           my $new_data = $self->_parse_dataproto($data_spec, $data, $ele);
           $new_data->{__root_data__} = $data->{__root_data__}||$data;
           $self->_render_recursive($new_data, $ele, $new_directives);
        }
      } else {
        die  "no $css at ${\$dom->to_string}"
      }
    } else {
      if(my $col = ($css eq '.' ? $dom->find('*') : $dom->find($css))) {
        $col->reverse->each( sub {
          my ($ele, $cnt) = @_;
          my $value = $self->_parse_dataproto($tag, $data, $ele);
          return if $maybe_filter;

          if(blessed $value) {
            if($value->isa('Template::Pure')) {
              if($maybe_wrapper) {
                my $string = $value->render(+{%$data, $self->wrapper_data_key=>$self->encoded_string($ele)});
                $_->replace($string);
                return;
              } else {
                $value = $self->encoded_string($value->render($data));
              }
            } elsif($value->isa('OPTIONAL')) {
              return;
            }
          }

          $value = $self->{filters}{escape_html}->($value);
          if($maybe_attr) {
            if($maybe_prepend) {
               $ele->attr($maybe_attr => "${\$ele->attr($maybe_attr)}$value");
            } elsif($maybe_append) {
               $ele->attr($maybe_attr => "$value${\$ele->attr($maybe_attr)}");
            } else {
               $ele->attr($maybe_attr => $value);
            }
          } else {
            if($maybe_prepend) {
              $ele->append_content($value);
            } elsif($maybe_append) {
              $ele->prepend_content($value);
            } else {
              $ele->content($value);
            }
          }
        });

      } else {
        die "no $css at ${\$dom->to_string}"
      }
    }
  }
  return $dom;
}

1;

=head1 NAME

Template::Pure - Perlish Port of pure.js

=head1 SYNOPSIS

    use Template::Pure;

    my $html_string = qq[
      <html>
        <head>
          <title>Sample Title</title>
        </head>
        <body>
          <ul class='people'>
            <li>Jane Grey
              <ul class='friends'>
                <li>John Doe</li>
              </ul>
            </li>
          </ul>
        </body>
      </html>];

    my %directives = (
      'title' => 'page_title',
      'ul[class="people"]' => {
        'person<-people' => {
          'li:first-child' => 'person.name',
          'ul[class="friends"]' => {
            'friend<-people.friends' => {
              'li:first-child' => 'friend',
            },
          },
        },
      },
    );

    my $pure = Template::Pure->new(
      template=>$html_string,
      directives=>\%directives);

    my %data = (
      page_title => 'Just Another Page',
      people => [
        { name => 'john Doe', age => 25, friends => [qw/Mark Mary Joe Jack Jason/] },
        { name => 'Bill On', age => 45, friends =>[qw/Srivinas Milton Aubrey/] },
    );

    my $rendered_template = $pure->render(\%data);

=head1 DESCRIPTION

HTML/XML Templating system, inspired by pure.js L<http://beebole.com/pure/>, with
some additions and modifications to make it more Perlish and to be more suitable
as a server side templating framework for larger scale needs instead of single page
web applications.

The core concept is you have your templates in pure HTML and create CSS style
matches to run transforms on the HTML to populate data into the template.  This allows you
to have very clean, truely logicless templates.  This approach can be useful when the HTML designers
know little more than HTML and related technologies.  It  helps promote separation of concerns
between your UI developers and your server side developers.  The main downside is that it
can place more work on the server side developers, who have to write the directives unless
your UI developers are able and willing to learn the minimal Perl required for that job.  Also
since it the CSS matching directives are based on the document structure, it can lead to onerous
tight binding between yout document structure and the layout/display logic.  For example due to
some limitations in the DOM parser, you might have to add some extra markup just so you have a
place to match, when you have complex and deeply nested data.  Lastly most UI
designers already are familiar with some basic templating systems and might really prefer to
use that so that they can maintain more autonomy and avoid the additional learning curve that
L<Template::Pure> will requires (most people seem to find its a bit more effort to learn off
the top compared to more simple systems like Mustache or even L<Template::Toolkit>.

Although inspired by pure.js L<http://beebole.com/pure/> this module attempts to help mitigate some
of the listed  possible downsides with additional features that are a superset of the original 
pure.js specification.  These additional features are intended to make it more suitable as a general
purpose server side templating system.

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
      template = $html,
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
      template = $html,
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
        'h1#title' => \'title',
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

=head2 Coderef - Programmatically replace the value indicated

    my $html = qq[
      <div>
        Hello <span id='name'>John Doe</span>!
      </div>
    ];

    my $pure = Template::Pure->new(
      template = $html,
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

B<NOTE>: If instead of returning simple value, you return a reference (like an ArraRef,
a HashRef, or an object) we act on that value as if it was the original action.  For
example if your anonymous subroutine returns an Arrayref, we assume its a list of
directives, and described.

B<NOTE>: It might be a good idea to try and maintain as much implementation independence
from you $data model as possible.  That way if later you change your $data from a hashref
to an instance of an object you won't break your code.  One way to help achieve this is
to use L<Template::Pure>'s data lookup helper methods (which support dot notation and more
as described below.  For example consider re-writing the above example like this:

    my $pure = Template::Pure->new(
      template = $html,
      directives => [
        '#name' => sub {
          my ($instance, $dom, $data) = @_;
          return $instance->data_at_path($data, 'id.first_name') .' '. 
            $instance->data_at_path($data, 'id.last_name') ; 
        },
      ]
    );

=head Arrayref - Run directives under a new DOM root

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
in a complext template with a lot of organization you might find this leads to more readable and
concise directives. It can also promote reusability.

=head2 Hashref - Move the root of the Data Context

Just like it may be valuable to move the root DOM context to an inner node, sometimes you'd
like to move the root of the current Data context to a path point.  This can result in cleaner
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
      template = $html,
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

=head2 Hashref - Remap or replace the current data context

Sometimes you wish to build an altered or new data context.

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
        '#contact' => {
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


=head2 Hashref - Create a Loop

Besides moving the current data context, setting the value of a match spec key to a
hashref can be used to perform loops over a node, such as when you wish to create
a list:

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
        '#names' => {
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
an iterator interface (see below).   If an object does not provide this interface you
may provide a 'coerce_iterator' key as described below.

For each item in the array we render the selected node against that data and
add it to parent node.  So the originally selected node is completely replaced by a
collection on new nodes based on the data.  Basically just think you are repeating over the
node value for as many times as there is items of data.

In the case the referenced data is explicitly set to undefined, the full node is
removed (the matched node, not just the value).

B<NOTE>: This behavior is somewhat different from pure.js, our inspiration.  Changes
have been made to be more consistent with our extended behavior.

=head3 Special value injected into a loop

When you create a loop we automatically add a special data key called 'i' (or 'ii', 'iii', etc
should an 'i' already exist) which is an object that contains meta data on the current state of the
loop. Fields that can be referenced are:

=over 4

=item value

An alias to the current value of the iterator.

=item current_index

The current index of the iterator (starting from 0.. or from the first key in a hashref or fields
interator).

=item last_index

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
        <dt>property</dt>
        <dd>value</dd>
      </dl>];

    my $pure = Template::Pure->new(
      template = $html,
      directives => [
        'dl#dlist' => {
          'property<-author' => [
            'dt' => 'i.current_index',
            'dd' => 'property',
          ],
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

    <dl id='dlist'>
      <dt>first_name</dt>
      <dd>John</dd>
      <dt>last_name</dt>
      <dd>Napiorkowski</dd>
      <dt>email</dt>
      <dd>jjn1056@yahoo.com</dd>
    </dl>

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

=item sort

Accepts an anonymous subroutine whos interface is object specific
but who's required return valid is a new object that does the iterator
interface and whoc provides display specific sorting rules.

=back

=head3 Sorting and filtering a Loop

You may provide a custom anonymous subroutine to provide a display
specific order to your loop.  For simple values such as Arrayrefs
and hashrefs this is simple:

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
        '#names' => {
          'name<-names' => [
            '.first-name' => 'name.first',
            '.last-name' => 'name.last',
          ],
          'sort' => sub {
            my ($template, $a, $b) = @_;
            return $a->last cmp $b->last;
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

So you have a key 'sort' at the same level as the loop action declaration
which is an anonynous subroutine that takes three arguments, the first being
a reference to the template object, followed by the $a and $b items to be
compared for example as in:

    my @display = sort { $a->last cmp $b->last } @list;

If your iterator is over an object the interface is slightly more complex since
we allow for the object to provide a sort method based on its internal needs.
For example if you have a L<DBIx::Class::Resultset> as your iterator, you may
wish to order your display at the database level:

    'sort' => sub {
      my ($template, $iterator) = @_;
      return $iterator->order_by_last_name;
    },

We recommend avoiding implimentation specific details when possible (for example
in L<DBIx::Class> use a custom resultset method, not a ->search query.).

=head3 Perform a 'grep' on your loop items

You may wish for the purposes of display to skip items in your loop.  Similar to
'sort', you may create a 'grep' key that returns either true or false to determine
if an item in the loop is allowed (works like the 'grep' function).

    # Only show items where the value is greater than 10.
    'grep' => sub {
      my ($template, $item) = @_;
      return $item > 10; 
    },

Just like with 'sort', if your iterator is over an object, you recieve that
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

Alternatively you can set the value of 'display_fields' to a code reference,
which when invoked will get the template object and the object to be iterated
over:

    directives => [
      '#meta' => {
        'field<-info' => [
            '.name' => 'field.key',
            '.value' => 'field.value',
          ],
          'display_fields' => sub {
            my ($template, $object) = @_;
            return $object->columns;
          },
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

    my $parent_html = qq[
      <html>
        <head>
          <title>Title</title>
        </head>
        <body>
          Example
        </body>
      </html>
    ];

    my $parent = Template::Pure->new(
      template = $parent_html,
      directives => [
        'title' => 'title',
        'body' => 'body',
      ]);

    my $page_html = qq[
      <html>
        <title>Welcome Page</title>
        <body>
          <div id="content">Page Content</div>
        </body>
      </html>
    ];

    my $page = Template::Pure->new(
      template = $page_html,
      directives => [
        '^html' => {
          {
            'title' => \'title',
            'body' => \'body',
          }, $parent,
        },
        '#content' => 'content',
      ]);

    my %data = (
      content => $article_text,
    );

    print $pure->render(\%data);

Results in:

    <html>
      <head>
        <title>Welcome Page</title>
      </head>
      <body>
        <div id="content">$article_text</div>
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
In this case you may prefix 'maybe:' to your path part, which will surpress
an error in the case the requested path does not exist:

In this case instead of returning an error we treat the path as though it
returned 'undefined' (which means we trim out the matching node).

TODO: do we need both 'optional' for return undef on paths that don't exist
and 'maybe' to handle th case when the path exists but returns undef?

    directives => [
      'title' => 'meta.title',
      'copyright => 'meta.license_info.maybe:author_name',
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

Using the 'maybe:' modifier can be useful when you have a complex data
context with possible optional paths and empty results (for example if
you are following a L<DBIx::Class> relationship graph you might have
optional relationships.)

In addition to searching a path using dot notation, you can change the
current path with '/' and '../'.  Using '../' moves you up one level
(returns you to the preview path) while using '/' moves you back to the root
context.  Both these are only in effect for the action that is using them.

=head2 Using Placeholders in your Actions

Sometimes it makes sense to compose your replacement value of several
bits of information.  Although you could do this with lots of extra 'span'
tags, sometimes its much more clear and brief to put it all together.  For
example:

    my $pure = Template::Pure->new(
      template => $html,
      directives => [
        '#content' => 'Hi #{name}, glad to meet you on #{today}',
      ]
    );

In the case your value does not refer itself to a path, but instead contains
one or more placeholders which are have data paths inside them.  These data
paths can be simple or complex, and even contain filters:

    my $pure = Template::Pure->new(
      template => $html,
      directives => [
        '#content' => 'Hi #{name | uc}, glad to meet you on #{today}',
      ]
    );

=head2 Filtering your data

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

=item '@': Select an attributes within the current node

=item '+': Append or prepend a value

B<NOTE> Can be combined with '@' to append / prepend to an attribute.

=item '^': Replace current node completely

=item '|': Run a filter on the current node

    'body|' => sub {
      my ($template, $dom, $data) = @_;
      $dom->find('p')->each( sub {
        $_->attr('data-pure', 1);
      });
    }

=back 


=head1 Overlay ???

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
  

  directives => [
    'title' => 'story.title',
    ['body', {
      inner_header => 'story.headline',
      ... => \'#body'
    }] => $inner, ... ];
  ],


need a proxy object when injecting i and content

=cut
