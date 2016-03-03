use Test::Most;
use Template::Pure::Utils;

# Helper function to make the tests less verbose
sub spec { +{ Template::Pure::Utils::parse_match_spec(shift) } }

# Test cases
is_deeply spec('title'), +{mode=>'replace', css=>'title', target=>'content'};
is_deeply spec('^title'), +{mode=>'replace', css=>'title', target=>'node'};
is_deeply spec('+title'), +{mode=>'prepend', css=>'title', target=>'content'};
is_deeply spec('title+'), +{mode=>'append', css=>'title', target=>'content'};
is_deeply spec('^+title'), +{mode=>'prepend', css=>'title', target=>'node'};
is_deeply spec('^title+'), +{mode=>'append', css=>'title', target=>'node'};
is_deeply spec('a@href'), +{mode=>'replace', css=>'a', target=>\'href'};
is_deeply spec('+a@href'), +{mode=>'prepend', css=>'a', target=>\'href'};
is_deeply spec('a@href+'), +{mode=>'append', css=>'a', target=>\'href'};
is_deeply spec('a#link@href'), +{mode=>'replace', css=>'a#link', target=>\'href'};
is_deeply spec('+a#link@href'), +{mode=>'prepend', css=>'a#link', target=>\'href'};
is_deeply spec('a#link@href+'), +{mode=>'append', css=>'a#link', target=>\'href'};
is_deeply spec('@href'), +{mode=>'replace', css=>'.', target=>\'href'};
is_deeply spec('^.'), +{mode=>'replace', css=>'.', target=>'node'};
is_deeply spec('html|'), +{mode=>'filter', css=>'html', target=>''};

done_testing;
