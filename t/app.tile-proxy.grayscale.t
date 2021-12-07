use strict;
use warnings;

use lib qw(lib);

use Test::More tests => 4;
use Test::Deep;
use Plack::Test;
use HTTP::Request::Common;
use Test::MockObject;
use Image::Magick;
use File::Spec::Functions qw(catfile);

use_ok('App::TileProxy::Grayscale');

my $ua_mock = Test::MockObject->new();
my $mock_tile_data = do {
	open(my $tile_fh, '<', catfile('t', 'testdata', 'tile.png'))
		or die 'Failed to open test file: ' . $!;
	local $/;
	<$tile_fh>;
};
our $mock_response = {
	success => 1,
	content => $mock_tile_data,
	headers => {
		'cache-control' => 'max-age=20435',
		'expires'       => 'Wed, 08 Dec 2021 02:24:53 GMT',
	}
};
$ua_mock->mock(get => sub {
	$mock_response
});

my $app = App::TileProxy::Grayscale->new({
	layers => {
		test => 'http://tiles.example.com/tiles/{z}/{y}/{x}.png',
	},
	ua     => $ua_mock,
});

subtest 'basic tile retrieval and header forwarding' => sub {
	plan tests => 10;

	test_psgi($app, sub {
		my ($cb) = @_;

		my $response = $cb->(GET '/test/1/1/1.png');
		is($response->code(), 200, 'tile retrieved');
		is($response->content_type(), 'image/png', 'PNG mime type ok');
		is($response->content_length(), length $response->content(), 'content length ok');
		is($response->header('Cache-Control'), 'max-age=20435', 'cache control ok');
		is($response->header('Expires'), 'Wed, 08 Dec 2021 02:24:53 GMT', 'expires ok');

		$response = $cb->(GET '/test/1/1/1.jpg');
		is($response->code(), 200, 'tile retrieved');
		is($response->content_type(), 'image/jpeg', 'JPEG mime type ok');
		is($response->content_length(), length $response->content(), 'content length ok');
		is($response->header('Cache-Control'), 'max-age=20435', 'cache control ok');
		is($response->header('Expires'), 'Wed, 08 Dec 2021 02:24:53 GMT', 'expires ok');
	});
};


subtest 'grayscale conversion' => sub {
	plan tests => 4;

	test_psgi($app, sub {
		my ($cb) = @_;

		my $response = $cb->(GET '/test/1/1/1.png');
		my @pixel = get_pixel($response->content(), 64, 64);
		cmp_deeply(\@pixel, [
			num(13800, 100),
			num(13800, 100),
			num(13800, 100),
		], 'red conversion ok');
		@pixel = get_pixel($response->content(), 64 + 128, 64);
		cmp_deeply(\@pixel, [
			num(46700, 100),
			num(46700, 100),
			num(46700, 100),
		], 'green conversion ok');
		@pixel = get_pixel($response->content(), 64, 64 + 128);
		cmp_deeply(\@pixel, [
			num(4600, 100),
			num(4600, 100),
			num(4600, 100),
		], 'blue conversion ok');
		@pixel = get_pixel($response->content(), 64 + 128, 64 + 128);
		cmp_deeply(\@pixel, [
			0,
			0,
			0,
		], 'black conversion ok');
	});
};


subtest 'errors' => sub {
	plan tests => 8;

	test_psgi($app, sub {
		my ($cb) = @_;

		my $response = $cb->(GET '/test/1/1/1.tif');
		is($response->code(), 404, 'tif not supported');

		$response = $cb->(GET '/test/x/y/z.png');
		is($response->code(), 404, 'invalid zoom/x/y');

		$response = $cb->(GET '/invalid/1/1/1.png');
		is($response->code(), 404, 'invalid layer');

		$response = $cb->(GET '/test');
		is($response->code(), 404, 'missing zoom/x/y');

		local $mock_response = {
			success => 0,
			status  => 599,
			content => 'Fake connection failed',
			reason  => 'Internal error',
		};
		$response = $cb->(GET '/test/1/1/1.png');
		is($response->code(), 599, 'internal error status');
		is($response->content(), 'Internal error', 'error message ok');

		local $mock_response = {
			success => 0,
			status  => 404,
			reason  => 'Not found',
		};
		$response = $cb->(GET '/test/1/1/1.png');
		is($response->code(), 404, 'tile not found');
		is($response->content(), 'Not found', 'error message ok');
	});
};


sub get_pixel {
	my ($image_data, $x, $y) = @_;

	my $magick = Image::Magick->new();
	$magick->BlobToImage($image_data);
	return $magick->GetPixels(
		x      => $x,
		y      => $y,
		map    => 'RGB',
		width  => 1,
		height => 1
	);
}
