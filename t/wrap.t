use Test::Most;
use Template::Pure;

ok my $wrapper_html = qq[
  <section>Example Wrapped Stuff</section>];

ok my $wrapper =  Template::Pure->wrapper(
  'section' => $wrapper_html
);

ok my $to_wrap_html = qq[
  <html>
    <head>
      <title>Page Title: </title>
    </head>
    <body>
      <div>foo<span id='inner'>ffff</span></div>
      <div>bar
        <div>baz</div>
      </div>
    </body>
  </html>
];

ok my $to_wrap = Template::Pure->new(
  template=>$to_wrap_html,
  directives=> [
    'title+' => 'meta.title',
    '{div}' => 'wrapper',
    'span#inner' => {
      meta => [
        '.' => 'author',
      ],
    },
  ]
);

ok my $rendered_template = $to_wrap->render({
  meta => { title=>'My Title', author=>'jnap' },
  wrapper => $wrapper,
});

warn $rendered_template;

done_testing;
