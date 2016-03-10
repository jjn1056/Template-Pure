use Test::Most;
use Template::Pure;
use DOM::Tiny;

ok my $html = q[
  <html>
    <head>
      <title>Page Title</title>
    </head>
    <body>
      <p id="story">Some Stuff</p>
      <p id="footer">...</p>
    </body>
  </html>
];

ok my $pure = Template::Pure->new(
  template=>$html,
  directives=> [
    '#story' => '={meta.title | upper}: ={story} on ={meta.date}',
    '#footer' => '={meta.title} on ={meta.date}',
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

is $dom->at('#story ')->content, 'INNER STUFF XXXXXXXXXXXXXXXXXXXX on 1/1/2020';
is $dom->at('#footer')->content, 'Inner Stuff on 1/1/2020';

done_testing; 

