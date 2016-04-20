use Test::Most;
use Template::Pure;

ok my $foot_html = qq[
  <span id="time">current time</span>];

ok my $foot = Template::Pure->new(
  template=>$foot_html,
  directives=> [
    '#time' => 'time',
  ]);

ok my $base_html = q[
  <html>
    <head>
      <title>Page Title: </title>
    </head>
    <body>
      <div id='story'>Example Story</div>
      <?pure-include src='foot' ctx='meta'?>
    </body>
  </html>
];

ok my $base = Template::Pure->new(
  template=>$base_html,
  directives=> [
    'title+' => 'meta.title',
  ]
);

ok my $string = $base->render({
  meta => {
    title=>'My Title',
    author=>'jnap',
    time => scalar(localtime),
  },
  foot => $foot,
});

ok my $dom = DOM::Tiny->new($string);

#is $dom->at('title')->content, 'Page Title: My Title';
#is $dom->at('#foo span')->content, 'foo';
#is $dom->at('#bar span')->content, 'bar';

warn $string;

done_testing;

