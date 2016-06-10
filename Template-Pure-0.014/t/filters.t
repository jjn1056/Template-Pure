use utf8;
use Test::Most;
use DateTime;
use Template::Pure::Filters;

is Template::Pure::Filters::format(undef, '2.00001', '%.2f'), '2.00';
is Template::Pure::Filters::strftime(undef, DateTime->new(year=>2016), '%Y'), '2016';
is Template::Pure::Filters::uri_escape(undef, "http://www.host.com/path?a=1&b=2"), 'http%3A%2F%2Fwww.host.com%2Fpath%3Fa%3D1%26b%3D2';
is Template::Pure::Filters::uri_escape_utf8(undef, "http://www.host.com/❤"), 'http%3A%2F%2Fwww.host.com%2F%E2%9D%A4';
is Template::Pure::Filters::truncate(undef, 'abcdefghij', 100), 'abcdefghij';
is Template::Pure::Filters::truncate(undef, 'abcdefghij', 5), 'abcde';
is Template::Pure::Filters::truncate(undef, 'abcdefghij', 8, '...'), 'abcde...';
is Template::Pure::Filters::truncate(undef, 'abcde', 8, '...'), 'abcde';
is Template::Pure::Filters::repeat(undef, 'abc', 3), 'abcabcabc';
is Template::Pure::Filters::remove(undef, 'abcabca', 'a'), 'bcbc';
is Template::Pure::Filters::remove(undef, 'abcabca', qr/[ac]/), 'bb';
is Template::Pure::Filters::comma(undef, '10000'), '10,000';

done_testing;
