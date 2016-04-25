use Test::Most;
use Template::Pure;

ok my $story_html = qq[
  <section>
    <h1>story title</h1>
  </section>];

ok my $story = Template::Pure->new(
  template=>$story_html,
  directives=> [
    '^h1+' => 'content',
  ]);

ok my $foot_html = qq[
  <span id="time">current time</span>];

ok my $foot = Template::Pure->new(
  template=>$foot_html,
  directives=> [
    '#time' => 'time',
  ]);

ok my $base_html = q[
  <html>
    <head>
      <title>Page Title: </title>
    </head>
    <body>
      <?pure-wrapper src='includes.story'?>
      <div id='story'>Example Story</div>
      <?pure-include src='includes.foot' ctx='meta'?>
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
  includes => {
    foot => $foot,
    story => $story,
  }
});

ok my $dom = Mojo::DOM58->new($string);

#is $dom->at('title')->content, 'Page Title: My Title';
#is $dom->at('#foo span')->content, 'foo';
#is $dom->at('#bar span')->content, 'bar';

warn $string;

done_testing;

__END__

output like

  <html>
    <head>
      <title>Page Title: My Title</title>
    </head>
    <body> 
      <section>
        <h1>story title</h1>
        <div id="story">
          XXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
        </div>
      </section>  
      <span id="time">Mon Apr 25 09:29:45 2016</span>
    </body>
  </html>
