use Test::Most;
use Template::Pure;
use Mojo::DOM58;


ok my $html = qq[
  <dl id='dlist'>
    <section>
    <dt>property</dt>
    <dd>value</dd>
    </section>
  </dl>];

ok my $pure = Template::Pure->new(
  template => $html,
  directives => [
    'dl#dlist section' => {
      'property<-author' => [
        'dt' => 'i.index',
        'dd' => 'property',
      ],
      order_by => sub {
        my ($hashref, $a_key, $b_key) = @_;
        $hashref->{$a_key} cmp $hashref->{$b_key};
      }
    },
  ]
);

ok my %data = (
  author => {
    first_name => 'John',
    last_name => 'Napiorkowski',
    email => 'jjn1056@yahoo.com',
  },
);


ok my $string = $pure->render(\%data);
ok my $dom = Mojo::DOM58->new($string);

is $dom->find('section')->[0]->at('dt')->content, 'first_name';
is $dom->find('section')->[0]->at('dd')->content, 'John';
is $dom->find('section')->[1]->at('dt')->content, 'last_name';
is $dom->find('section')->[1]->at('dd')->content, 'Napiorkowski';
is $dom->find('section')->[2]->at('dt')->content, 'email';
is $dom->find('section')->[2]->at('dd')->content, 'jjn1056@yahoo.com';

done_testing; 
