use Test::Most;
use Template::Pure;

ok my $html = qq[
  <html>
    <head>
      <title>Page Title</title>
    </head>
    <body>
    </body>
  </html>
];

ok my $pure = Template::Pure->new(
  template=>$html,
  directives=> [
    'title' => 'meta.title',
    'body' => 'content',
    },
  ]
);

ok my $data = +{
  meta => {
    title=>'My Title',
    author=>'jnap',
  },
  content => q[
    Are you doomed to discover that you never recovered from the narcoleptic
    country in which you once stood? Where the fire's always burning, but
    there's never enough wood?
  ],
};

done_testing;



