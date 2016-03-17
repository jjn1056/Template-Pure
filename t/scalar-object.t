use Test::Most;
use Template::Pure;
use DOM::Tiny;

ok my $wrapper_html = qq[
  <section>Example Wrapped Stuff</section>];

ok my $wrapper = Template::Pure->new(
  template=>$wrapper_html,
  directives=> [
    'section' => 'content',
  ]);

ok my $template = qq[
 <html>
    <head>
      <title>Title Goes Here!</title>
    </head>
    <body>
      <p>Hi Di Ho!</p>
    </body>
  </html>    
];

ok my @directives = (
  title => 'title',
  body => 'content',
);

ok my $pure = Template::Pure->new(
  template => $template,
  directives => \@directives);

ok my $data = +{
  title => 'Scalar objects',
  content => $wrapper,
};

my $string = $pure->render($data);

warn $string;

done_testing;
