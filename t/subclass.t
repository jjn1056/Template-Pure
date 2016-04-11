
BEGIN {
  use Test::Most;
  use Template::Pure;
  plan skip_all => "Moo required, err $@" 
    unless eval "use Moo; 1";
}

{
  package Local::Template::Pure::Custom;

  use Moo;
  extends 'Template::Pure';

  has 'version' => (is=>'ro', required=>1);

  sub time { scalar localtime }
}

ok my $html_template = qq[
  <html>
    <head>
      <title>Page Title</title>
    </head>
    <body>
      <div id='version'>Version</div>
      <div id='main'>Test Body</div>
      <div id='foot'>Footer</div>
    </body>
  </html>
];

ok my $pure = Local::Template::Pure::Custom->new(
  version => 100,
  template=>$html_template,
  directives=> [
    'title' => 'meta.title',
    '#version' => 'self.version',
    '#main' => 'story',
    '#foot' => 'self.time',

  ]
);

ok my $data = +{
  meta => {
    title=>'A subclass',
    author=>'jnap',
  },
  story => 'XXX',
};

ok my $string = $pure->render($data);
ok my $dom = DOM::Tiny->new($string);

#is $dom->at('title'), '<title>Doomed Poem</title>';
#like $dom->at('body'), qr/Are you doomed to discover that/;

warn $string;

done_testing;
