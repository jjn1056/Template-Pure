use Test::Most;
use Template::Pure;

ok my $html_string = qq[
  <html>
    <head>
      <title>Sample Title</title>
    </head>
    <body>
      <h1 id='headline'>Example Headline</h1>
      <ul id='people'>
        <li class='person'>
          <span>Jane Grey</span>:<span class="age">11</span>
          <ul class='friends'>
            <li>
              James Grey
            </li>
          </ul>
        </li>
      </ul>
      <a id='return'>Return</a>
      <p id='author'>Example Author</p>
      <a id='email' href='mailto:'>:Is the Author's Email</a>
      <ol id='cite'>
        Citations
        <li>
          <span>Cite Ibid</span>
        </li>
        <p>All cites relative...</p>
      </ol>
      <p id='copyright'>XXXX<span>asdasd</span>sadasd</p>
    </body>
  </html>];

ok my %directives = (
  'title' => 'page_title',
  'h1#headline' => sub {
    my ($template, $dom, $data) = @_;
    return $template->data_at_path($data, 'random_stuff');
  },
  'a#return@href' => 'return_url',
  '#author' => '#{author.first_name} #{author.last_name}',
  '#email@href+' => 'author.email',
  '+#email' => 'author.email',
  '#copyright' => 'meta.copyright',
  '#cite li' => {
    'cite<-citations' => {
      'span' => 'cite',
      'span@id' => 'cite_#{i.index}',
    }
   },
  'ul#people li.person' => {
    'person<-people' => {
      'span' => 'person.name',
      'span.age' => 'person.age',
      'ul.friends li' => {
        'friend<-person.friends' => {
          '.' => 'friend',
          '@id' => 'friend',
        },
      }
    },
  },
);

ok my $pure = Template::Pure->new(
  template=>$html_string,
  directives=>\%directives);

ok my %data = (
  random_stuff => 'New Headline',
  page_title => 'Just Another Page',
  return_url => 'https://localhost/basepage.html',
  meta => {
    copyright => 2016,
    license => 'Artistic',
  },
  author => {
    first_name => 'John',
    last_name => 'Napiorkowski',
    email => 'jjn1056@yahoo.com',
  },
  citations => [qw/aa bb cc dd/],
  people => [
    { name => 'john Doe', age => 25, friends => [qw/Mark Mary Joe Jack Jason/] },
    { name => 'Bill On', age => 45, friends =>[qw/Srivinas Milton Aubrey/]}]);

ok my $rendered_template = $pure->render(\%data);

warn($rendered_template);

done_testing;


__END__

## TODO

interators on objects and hashes

>include.html




