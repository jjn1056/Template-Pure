use Test::Most;
use Template::Pure;

ok my $master_html = q[
  <html>
    <head>
      <title>Example Title</title>
      <link rel="stylesheet" href="/css/pure-min.css"/>
        <link rel="stylesheet" href="/css/grids-responsive-min.css"/>
          <link rel="stylesheet" href="/css/common.css"/>
      <script src="/js/3rd-party/angular.min.js"></script>
        <script src="/js/3rd-party/angular.resource.min.js"></script>
    </head>
    <body>
      <section id="content">...</section>
      <p id="foot">Here's the footer</p>
    </body>
  </html>
];

ok my $master = Template::Pure->new(
  template=>$master_html,
  directives=> [
    'title' => 'title',
    'head+' => 'scripts',
    'body section#content' => 'content',
  ]);

ok my $story_html = qq[
  <section>
    <h1>story title</h1>
    <p>By </p>
  </section>];

ok my $story = Template::Pure->new(
  template=>$story_html,
  directives=> [
    '^p+' => 'content',
    'p+' => 'author',
  ]);

ok my $foot_html = qq[
  <span id="time">current time</span>];

ok my $foot = Template::Pure->new(
  template=>$foot_html,
  directives=> [
    '#time' => 'time',
  ]);

ok my $base_html = q[
  <?pure-master src='lib.master'
    title=\'title'
    scripts=\'^head script' 
    content=\'body'?>
  <html>
    <head>
      <title>Page Title: </title>
      <script>
      function foo(bar) {
        return baz;
      }
      </script>
    </head>
    <body>
      <?pure-wrapper src='lib.story' ctx='meta'?>
      <div id='story'>Example Story</div>
      <?pure-include src='lib.foot' ctx='meta'?>
    </body>
  </html>
];

ok my $base = Template::Pure->new(
  template=>$base_html,
  directives=> [
    'title+' => 'meta.title',
    '#story' => sub { 'XXX'x10 },
  ]
);

ok my $string = $base->render({
  meta => {
    title=>'My Title',
    author=>'jnap',
    time => scalar(localtime),
  },
  lib => {
    foot => $foot,
    story => $story,
    master => $master,
  }
});

ok my $dom = Mojo::DOM58->new($string);

#is $dom->at('title')->content, 'Page Title: My Title';
#is $dom->at('#foo span')->content, 'foo';
#is $dom->at('#bar span')->content, 'bar';

warn $string;

done_testing;

__END__

output like:

  <html>
    <head>
      <title>Page Title: My Title</title>
      <link href="/css/pure-min.css" rel="stylesheet">
        <link href="/css/grids-responsive-min.css" rel="stylesheet">
          <link href="/css/common.css" rel="stylesheet">
      <script src="/js/3rd-party/angular.min.js"></script>
        <script src="/js/3rd-party/angular.resource.min.js"></script>
          <script>
            function foo(bar) {
              return baz;
            }
          </script>
      </head>
    <body>
      <section id="content"> 
        <section>
          <h1>story title</h1>
          <p>By jnap</p>
          <div id="story">
            XXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
          </div>
        </section>
        <span id="time">Mon Apr 25 16:49:55 2016</span>
      </section>
      <p id="foot">Here&#39;s the footer</p>
    </body>
  </html>
