use Test::Most;
use Template::Pure::Utils;
use Template::Pure::DataContext;

# Helper function to make the tests less verbose
sub parse_data { Template::Pure::Utils::parse_data_spec(shift) }
sub data_context { Template::Pure::DataContext->new(shift) }

{
  my $data = {
    title => 'About Me',
    meta => {
      name => 'john',
      dob => '02/13/1969',
    },
    deep => {
      aaa => {
        bbb => {
          ccc => 100,
        },
      },
    },
  };

  ok my $c = data_context $data;
  is $c->at( parse_data 'title'), 'About Me';
  is $c->at( parse_data 'meta.name'), 'john';
  is $c->at( parse_data 'deep.aaa.bbb.ccc'), '100';
  #is $c->at( parse_data 'deep.aaa.bbb.optional:eee'), undef;


  #is $c->at( parse_data 'optional:boo'), undef;
  die "Test unfinished, not doing optional maybe right";
  
  use Devel::Dwarn;
  Dwarn $c->at( parse_data 'optional:boo')->value;

}
done_testing;
