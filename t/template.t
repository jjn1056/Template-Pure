use Test::Most;
use Template::Pure;
use DOM::Tiny;

ok my $inner_html = q[
  <h1>Header</h1>
  <section id="content">...</p>
];

ok my $inner = Template::Pure->new(
  template=>$inner_html,
  directives=> [
    'h1' => 'meta.title',
    '#content' => 'content',
]);


ok my $html = q[
  <html>
    <head>
      <title>Page Title</title>
    </head>
    <body>
      <p id="story">Some Stuff</p>
    </body>
  </html>
];

ok my $pure = Template::Pure->new(
  template=>$html,
  directives=> [
    '^body p'=>$inner,
    '#story' => 'story',
]);

ok my $data = +{
  meta => {
    title => 'Inner Stuff',
    date => '1/1/2020',
  },
  story => 'XX' x 10,
};

ok my $string = $pure->render($data);
ok my $dom = DOM::Tiny->new($string);

is $dom->at('body section#content p#story ')->content, 'XXXXXXXXXXXXXXXXXXXX';
is $dom->at('body h1')->content, 'Inner Stuff';

done_testing; 
