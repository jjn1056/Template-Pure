use Test::Most;
use Template::Pure;

ok my $status_template = qq[
<dl id='game'>
  <dt>Status</dt>
  <dd id='status'>Tie</dd>
  <dt>Pending Move</dt>
  <dd id='current-move'>N/a</dd>
  <dt>Who's Turn</dt>
  <dd id='whos-turn'>N/a</dd>
  <dt>Current Layout</dt>
  <?= include '_board' ?>
</dl>
];

ok my $status = Template::Pure->new(
  template=>$status_template,
  directives=> [
    '#status' => 'status',
    '#current-move' => '?current-move',
    '#whos-turn' => '?whos-turn',
  ]
);

ok my $html_template = qq[
<!doctype html>
<html lang="en">
  <head>
    <title id="df">Default Title</title>
    <meta charset="utf-8" />
      <meta name="description" content="Tic Tac Toe API">
        <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  </head>
  <body>
    <h1>Content goes here!</h1>
  </body>
</html>
];

ok my $html = Template::Pure->new(
  template=>$html_template,
  directives=> [
    'head+' => '?head',
    'title' => 'title',
    'body' => 'body',
  ]
);

ok my $new_game_template = qq[
<html>
  <head>
    <title>New Game</title>
  </head>
  <body id='new-game'>
    <h1>Information</h1>
      <dl>
        <dt>Time of Request</dt>
        <dd id='time'>Jan 1</dd>
        <dt>Requested Move</dt>
        <dd id='moves'>2</dd>
      </dl>
    <h1>Links</h1>
    <p>Your <a id='new_game_url'>new game</a></p>
    <h1>Current Game Status</h1>
  </body>
</html>
];

ok my $new_game = Template::Pure->new(
  template=>$new_game_template,
  directives=> [
    'html' => {
      '>html<' => {
        'merge::title' => 'title',
        'merge::body' => 'body',
      }
    },
    'dl' => {
      information => [
        'dd#time' => 'time',
        'dd#moves' => 'moves',
      ],
    },
    'a#new_game_url@href' => 'new_url',
    'body+' => {
      game => [
        '.' => '/status_include'
      ],
    }
  ]
);

warn $new_game->render(
  {
    html => $html,
    status_include => $status,
    new_url => 'https://localhost/new',
    information =>  {
      time => scalar(localtime),
      moves => 4,
    },
    game => {
      status => 'incomplete',
    },
  }
);


done_testing;
