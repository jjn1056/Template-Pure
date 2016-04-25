use Test::Most;
use Template::Pure;
use Mojo::DOM58;

ok my $html = q[
  <html>
    <head>
      <title>Page Title</title>
    </head>
    <body>
      <h1>Article Title</h1>
      <ol>
        <li>stuff</li>
      </ol>
      <div>End Stuff</div>
    </body>
  </html>
];

ok my $pure = Template::Pure->new(
  template=>$html,
  directives=> [
    'title' => 'settings.maybe:defaults.title',
    'body h1' => 'title',
    'body div' => 'optional:foot',
    'ol li' => {
      'person<-people' => [
        '.' => '={person} ={i.index}',
      ],
    },
  ],    
);

ok my $data = +{
  settings => {
    foo => 'bar',
    defaults => undef,
  },
  title => undef,
  people => undef,
};

ok my $string = $pure->render($data);
ok my $dom = Mojo::DOM58->new($string);

ok !$dom->at('title');
ok !$dom->at('ol li');
ok !$dom->at('body div');

done_testing; 
