package Template::Pure::Utils;
 
use strict;
use warnings;

sub parse_match_spec {
  my $spec = shift;
  my $maybe_target_node = ($spec=~s/^\^//);
  my $maybe_filter = ($spec=~s/\|$//);
  my $maybe_prepend = ($spec=~s/^(\+)//);
  my $maybe_append = ($spec=~s/(\+)$//);
  my ($css, $maybe_attr) = split('@', $spec);
  $css = '.' if $maybe_attr && !$css; # $css unlikely to be 0

  die "You need a CSS style match: '$spec'"
    unless $css;

  die "Can't add a filter when appending or prepending: '$spec'"
    if $maybe_filter && ($maybe_append || $maybe_prepend);

  die "Can't set a target when filtering: '$spec'"
    if $maybe_filter && ($maybe_target_node || $maybe_attr);

  die "Can't set a target attribute and target node: '$spec'"
    if $maybe_target_node && $maybe_attr;

  my $target = 'content';
  if($maybe_target_node) {
    $target = 'node';
  } elsif($maybe_attr) {
    $target = \$maybe_attr;
  }

  my $mode = 'replace';
  if($maybe_append) {
    $mode = 'append';
  } elsif($maybe_prepend) {
    $mode = 'prepend';
  } elsif($maybe_filter) {
    $mode = 'filter';
    $target = '';
  }

  return (
    css => $css,
    target => $target,
    mode => $mode,
  );
}


1;

=head1 NAME

Template::Pure::Utils - Utility Functions

=head1 SYNOPSIS

    For internal use

=head1 DESCRIPTION

Contains utility functions for L<Template::Pure>

=head1 FUNCTIONS

This package contains the following functions:

=head2 parse_match_spec ($template, $spec)

Given a directive match specification (such as '#head', 'title', 'p.links@href', ...) parse
it into a hash that defines how the match is to be performed.  Returns a hash with keys are
follows.

=over 4

=item css

This is the actual CSS match component ('p', '#id', '.class') or the special match indicator of
'.' for the current node.

=item target

This is the indicator of the replacement target for the match.  Can be: 'node', 'content', \'$attribute':

=over 4

=item content

    Example Match Specifiction: 'p.headline', 'title', '#id'

This is the default value for target.  Indicates we will update the matched nodes' content.  For example the
content of node '<p>content</p>' is 'content'.  No special symbols are needed to indicate this target type.

=item \$attribute

    Example Match Specifiction: 'a#homepage@href', 'ul.links@class'

When the value of 'target' is a scalar reference, this indicates the update type to be an attribute on the current
matched node.  The dereferenced scalar is the name of the attribute.  If the attribute does not exist in the current
node this does not raise an exception, but rather we automatically add it.

It is an error to indicate both node and attribute targets.

B<NOTE> Should a match specification consist only of an attribute, we presume a 'css' value of '.'

=item node

    Example Match Specifiction: '^p.headline', '^#id'

Indicated a target of 'node', which means we will replace the entire matched node.  Indicated by a '^' appearing
as the first character of the match specification.

It is an error to indicate both node and attribute targets.

=back

=item mode

Defines the relationship, if any, between a new value from the data context and any existing information
in the template and the match location.  One of 'append', 'prepend', or 'replace', with 'replace' being the default.

=over 4

=item replace

    Example Match Specifiction: 'title', '#id', 'p.content@class'

The default behavior.  Needs no special indicators in the match specification.  Means the new value
completely replaces the match target.

=item append

    Example Match Specifiction: 'title+', '#id+', 'p.content@class+'

Match specifications that end with '+' will append to the indicated match (that is we place the
new value after the old value, preserving th old value.

It is an error to try to set both append and prepend mode on the same target.  It is also an error
to use append and prepend along with a filter indicator (see below).

When appending to a target of attribute where the attribute is 'class', we automatically add a ' ' (space)
between the appending value and any existing value.  This is a special case since generally a space
is required between classes in order for them to work as expected.

=item prepend

    Example Match Specifiction: '+body', '+p.content@class'

Match specifications that begin with a '+' (or '^+') indicate we expect to add the data context to the
front of the existing value, preserving the existing value.

It is an error to try to set both append and prepend mode on the same target.  It is also an error
to use append and prepend along with a filter indicator (see below).

When prepending to a target of attribute where the attribute is 'class', we automatically add a ' ' (space)
between the appending value and any existing value.  This is a special case since generally a space
is required between classes in order for them to work as expected.

=item filter

    Example Match Specification: 'html|', 'body|'

Means that we expect to run a filter callback on the matched node.  Useful when you want to make global
changes across the entire template.  Indicated by a '|' or pipe symbol.  Cannot be used with append,
prepend or any special target indicators (attributes or node).

We expect the action the be an anonymous subroutine.

=back

=head1 SEE ALSO
 
L<Template::Pure>.

=head1 AUTHOR
 
    John Napiorkowski L<email:jjnapiork@cpan.org>

But lots of this code was copied from L<Template::Filters> and other prior art on CPAN.  Thanks!
  
=head1 COPYRIGHT & LICENSE
 
Please see L<Template::Pure> for copyright and license information.

=cut 
