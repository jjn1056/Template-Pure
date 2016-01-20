use warnings;
use strict;

package Template::Pure;

use DOM::Tiny;
use Template::Pure::Iterator;
use Scalar::Util 'blessed';
use Data::Dumper;
use Devel::Dwarn;

sub new {
  my ($proto, %args) = @_;
  my $class = ref($proto) || $proto;
  my %attr = (
    dom => DOM::Tiny->new($args{template}),
    directives => $args{directives});

  return bless \%attr, $class;
}

sub render {
  my ($self, $data) = @_;
  my $dom = $self->_render_recursive(
    $data,
    $self->{dom},
    $self->{directives});
  return $dom->to_string;
}

sub _parse_match_spec {
  my ($self, $match_spec) = @_;
  my $maybe_append = $match_spec=~s/^(\+)// ? 1:0;
  my $maybe_prepend = $match_spec=~s/(\+)$// ? 1:0;
  my ($css, $maybe_attr) = split('@', $match_spec);
  $css = '.' if $maybe_attr && !$css; # not likely to be 0 so this is ok
  return ($css, $maybe_attr, $maybe_prepend, $maybe_append);
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
  my ($self, $tag, $data) = @_;
  my ($part, @more) = split('\.', $tag);
  my $value = $self->data_at_path($data, $part, @more); 
  return defined $value ? $value : die "No value for $tag in: ".Dumper $data;
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
    my ($css, $maybe_attr, $maybe_prepend, $maybe_append) = $self->_parse_match_spec($match);
    if(ref($tag) && ref($tag) eq 'HASH') {
      my $sort_cb = delete $tag->{sort};
      my $filter_cb = delete $tag->{filter};
      my $options = delete $tag->{options};
      if(my $ele = ($css eq '.' ? $dom : $dom->at($css))) {
        my ($data_spec, $new_directives) = %$tag;
        if($data_spec=~m/\<\-/) {
          my ($new_data_key, $current_key) = split('<-', $data_spec);
          my $iterator_proto = $self->_parse_dataproto($current_key, $data, $ele);
          my $iterator = Template::Pure::Iterator->from_proto($iterator_proto, $sort_cb, $filter_cb, $options);
          while(my $datum = $iterator->next) {
            my $new = DOM::Tiny->new($ele);
            my $new_dom = $self->_render_recursive(
              +{$new_data_key => $datum, i => $iterator},
              $new,
              $new_directives);
            $ele->prepend($new_dom);
          }
          $ele->remove($css); #ugly, but can't find a better solution...
        } else {
          # no iterator, just move the context.
           my $new_data = $self->_parse_dataproto($data_spec, $data, $ele);
           $self->_render_recursive($new_data, $ele, $new_directives);
        }
      } else {
        die  "no $css at ${\$dom->to_string}"
      }
    } else {
      if(my $ele = ($css eq '.' ? $dom->at('*') : $dom->at($css))) {
        my $value = $self->_parse_dataproto($tag, $data, $ele);
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

The core concept is you have your templates in nearly pure HTML and create CSS style
matches to run transforms on the HTML to populate data into the template.  This allows you
to have very clean, logicless templates.  This approach can be useful when the HTML designers
know little more than HTML and related technologies.  It  helps promote separation of concerns
between your UI developers and your server side developers.  The main downside is that it
can place more work on the server side developers, who have to write the CSS directives unless
your UI developers are able and willing to learn the minimal Perl required for that job.  Also
since it the CSS matching directives are based on the document structure, if can lead to onerous
tight binding between yout document structure and the layout/display logic.  For example due to
some limitations in the DOM parser, you might have to add some extra markup justso you have a
place to match, when you have complex and deeply nested data.  Lastly most UI
designers already are familiar with some basic templating systems and might really prefer to
use that so that they can maintain more autonomy.  This module attempts to help mitigate some
of these possible downsides with additional features that are a superset of the original 
pure.js specification.

=head1 AUTHOR
 
John Napiorkowski L<email:jjnapiork@cpan.org>
  
=head1 SEE ALSO
 
L<DOM::Tiny>, L<Catalyst::View::Template::Pure>.
 
=head1 COPYRIGHT & LICENSE
 
Copyright 2016, John Napiorkowski L<email:jjnapiork@cpan.org>
 
This library is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.
  
## maybe for the catalyst view...
<pure-param name="title" value="A Page"/> #Can be used to set defaults or template controlled fields
page.html
page-directives.json


maybe let <div data-pure-key="val">
=cut
