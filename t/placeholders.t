use Test::Most;
use Template::Pure;
use Mojo::DOM58;

ok my $html = q[
  <html>
    <head>
      <title>Page Title</title>
    </head>
    <body>
      <p id="story">Some Stuff</p>
      <p id="footer">...</p>
      <p id="last">...</p>
      <p id="bug1">...</p>
    </body>
  </html>
];

ok my $pure = Template::Pure->new(
  template=>$html,
  directives=> [
    'body ={story_target}' => '={meta.title | upper}: ={story} on ={meta.date}',
    '#footer' => '={meta.title} on ={meta.date} | upper',
    '#last' => '={meta.title} is the title | upper',
    '#bug1' => '={meta.date}/delete',

]);

ok my $data = +{
  story_target => '#story',
  meta => {
    title => 'Inner Stuff',
    date => '1/1/2020',
  },
  story => 'XX' x 10,
};

ok my $string = $pure->render($data);
ok my $dom = Mojo::DOM58->new($string);

#warn $string;

is $dom->at('#story ')->content, 'INNER STUFF: XXXXXXXXXXXXXXXXXXXX on 1/1/2020';
is $dom->at('#footer')->content, 'INNER STUFF ON 1/1/2020';
is $dom->at('#last')->content, 'INNER STUFF IS THE TITLE';
is $dom->at('#bug1')->content, '1/1/2020/delete';

done_testing; 
