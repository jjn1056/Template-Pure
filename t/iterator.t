use Test::Most;
use Template::Pure;
use DOM::Tiny;

ok my $html = q[
  <html>
    <head>
      <title>Page Title</title>
    </head>
    <body>
      <ul>
        <li><span>stuff</span>extra stuff</li>
      </ul>
      <ol>
        <li>stuff</li>
      </ol>

    </body>
  </html>
];

ok my $pure = Template::Pure->new(
  template=>$html,
  directives=> [
    'ul li' => {
      'person<-people' => [
        'span' => 'person',
      ],
    },
    'ol li' => {
      'person<-people' => [
        '.' => 'person',
      ],
      'order_by' => sub {
        my ($a, $b) = @_;
        return $b cmp $a;
      },
      'filter' => sub {
        return $_[0] =~m/ja/;
      },
    },
  ],    
);

ok my $data = +{
  people => [qw/john jack jane/],
};

ok my $string = $pure->render($data);
ok my $dom = DOM::Tiny->new($string);

is $dom->find('ul li')->[0]->content, '<span>john</span>extra stuff';
is $dom->find('ul li')->[1]->content, '<span>jack</span>extra stuff';
is $dom->find('ul li')->[2]->content, '<span>jane</span>extra stuff';
is $dom->find('ol li')->[0]->content, 'jane';
is $dom->find('ol li')->[1]->content, 'jack';

done_testing; 
