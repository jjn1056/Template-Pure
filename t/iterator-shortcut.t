use Test::Most;
use Template::Pure;
use Mojo::DOM58;

my $html = qq[
  <ol>
    <li>Things to Do...</li>
  </ol>
];

my $pure = Template::Pure->new(
  template => $html,
  directives => [
    'ol li' => {
      'task<-tasks' => 'task',
    },
  ]);

my %data = (
  tasks => [
    'Walk Dogs',
    'Buy Milk',
  ],
);

ok my $string = $pure->render(\%data);
ok my $dom = Mojo::DOM58->new($string);

is $dom->find('ol li')->[0]->content, 'Walk Dogs';
is $dom->find('ol li')->[1]->content, 'Buy Milk';
ok !$dom->find('ol li')->[3];

done_testing; 
