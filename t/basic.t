use Test::Most;
use Template::Pure;

ok my $include_html = qq[
  <meta charset="utf-8" />
  <meta name="description" content="Example Include">
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <script></script>
];

ok my $include = Template::Pure->new(
  template=>$include_html,
  directives=> [ 'script@src' => 'angular']
);

ok my $wrapper_html = qq[
  <div class='container'>Inside the container</div>
  ];

ok my $wrapper = Template::Pure->new(
  template=>$wrapper_html,
  directives=> [ 'div.container' => 'content']
);


ok my $html_string = qq[
  <html>
    <head>
      <title>Sample Title</title>
    </head>
    <body>
      <h1 id='headline'>Example Headline</h1>
      <dl id='dlist'>
        <dt>property</dt>
        <dd>value</dd>
      </dl>
      <ul id='people'>
        <li class='person'>
          <span>Jane Grey</span>:<span class="age">11</span>
          <ul class='friends'>
            <li>
              James Grey
            </li>
          </ul>
          <ol id="numbers">
            <li>(646)-708-1837</li>
          </ol>
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
      <div id='meta'>
        <p id='copyright'>ZZZ</p>
        <p id='license'>??</p>
      </div>
    </body>
  </html>];

ok my @directives = (
  'title' => 'page_title',
  'head+' => 'include',
  'h1#headline' => sub {
    my ($template, $dom, $data) = @_;
    return $template->data_at_path($data, 'random_stuff');
  },
  'body' => sub {
    my ($template, $dom, $data) = @_;
    return $template->encoded_string(
      $wrapper->render(
      +{ content=>$template->encoded_string($dom->content) }
    ));
  },
  'dl#dlist' => {
    'property<-author' => [
      'dt' => 'i.index',
      'dd' => 'property',
    ],
    'sort' => sub {
      my ($data, $a, $b) = @_;
      return lc($data->{$a}) cmp lc($data->{$b});
    },
    'filter' => sub {
      my ($key, $value) = @_;
      return $key =~m/_name/i;
    }
  },
  'a#return@href' => 'return_url',
  '#author' => '#{author.first_name} #{author.last_name}',
  '#email@href+' => 'author.email',
  '+#email' => 'author.email',
  '#copyright' => 'meta.copyright',
  'ol#cite' => {
    '>wrapper<' => {
      content => '.'
    },
    directives => [
      'li' => {
        'cite<-citations' => [
          'span' => 'cite',
          'span@id' => 'cite_#{i.index}',
        ],
        'sort' => sub {
          my ($arrayref, $a, $b) = @_;
          return $b cmp $a;
        },
        'filter' => sub {
          my $value = shift;
          return $value !~m/d/;
        },
      },
    ],
  },
  'ul#people li.person' => {
    'person<-people' => [
      'span' => 'person.name',
      'span.age' => 'person.age',
      'ul.friends li' => {
        'friend<-person.friends' => [
          '.' => 'friend',
          '@id' => 'friend |lc',
        ],
      },
      'ol#numbers li' => {
        'number<-person.numbers' => [
          '.' => sub {
            my ($template, $dom, $data) = @_;
            my @classes = ();
            push @classes, 'first' if $data->{i}->is_first;
            push @classes, 'even' if $data->{i}->is_even;
            push @classes, 'odd' if $data->{i}->is_odd;

            $dom->attr(class=>join(' ', @classes)) if @classes;
            return  $data->{i}->current_value;
          },
        ],
      }
    ],
  },
  '#meta' => {
    'meta' => [
      '#copyright' => 'copyright',
      '#license' => 'license',
    ],
  },
  'body|' => sub {
    my ($template, $dom, $data) = @_;
    $dom->find('p')->each( sub {
      $_->attr('data-pure', 1);
    });
  }
);

ok my $pure = Template::Pure->new(
  template=>$html_string,
  directives=>\@directives);

ok my %data = (
  angular => '/js/3rd-party/angular.resource.min.js',
  random_stuff => '<p>New Headline',
  page_title => 'Just Another Page<script></script>',
  return_url => 'https://localhost/basepage.html',
  include => $include,
  wrapper => $wrapper,
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
    { name => 'john Doe', age => 25, numbers => [qw/10 20 25/], friends => [qw/Mark Mary Joe Jack Jason/] },
    { name => 'Bill On', age => 45, numbers => [qw/35 42/], friends =>[qw/Srivinas Milton Aubrey/]}]);

ok my $rendered_template = $pure->render(
  \%data,
  [ 'title|' => sub {
    my ($t, $dom, $data) = @_;
    $dom->content(uc $dom->content);
  }]
);

warn($rendered_template);



done_testing;
