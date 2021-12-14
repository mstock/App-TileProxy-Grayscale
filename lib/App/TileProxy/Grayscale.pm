package App::TileProxy::Grayscale;

# ABSTRACT: Tile proxy which converts served tiles to grayscale

use strict;
use warnings;
use Carp;

use parent qw(Plack::Component);

use Plack::Util::Accessor qw(layers router forward_headers ua);
use HTTP::Tiny;
use Image::Magick;
use Router::Simple;

=head1 SYNOPSIS

In some e.g. C<app.psgi>:

	use strict;
	use warnings;

	use App::TileProxy::Grayscale;

	my $app = App::TileProxy::Grayscale->new({
		layers => {
			osm => 'https://some.tile.server/base/{z}/{x}/{y}.png',
		},
	})->to_app();

Run application with e.g. L<Starman|Starman>:

	starman --port 8080 app.psgi

Access tiles:

	http://localhost:8080/osm/{z}/{x}/{y}.png

=head1 DESCRIPTION

This L<Plack|Plack>/L<PSGI|PSGI> application acts as a reverse proxy for tile
servers which does a conversion of the served tiles to grayscale.

=head2 Dependencies

On Debian, the following command installs the required packages:

	apt install libplack-perl libimage-magick-perl librouter-simple-perl

L<Starman|Starman> can be installed as follows, but is only required when
running the application with it:

	apt install starman

=head1 PARAMETERS

=over

=item layers

Hash reference with layers to offer. The key will be part of the tile URLs while
the key is a regular tile URL template.

=item forward_headers

Array reference with response headers from the upstream tile server that should
be forwarded. Defaults to C<Cache-Control> and C<Expires> headers.

=item ua

L<HTTP::Tiny|HTTP::Tiny> instance to use as user agent for tile retrieval.

=back

=head1 METHODS

=cut

my %format = (
	jpg => 'image/jpeg',
	png => 'image/png',
);


=head2 prepare_app

Hook called by L<Plack::Component|Plack::Component> to prepare the application.

=cut

sub prepare_app {
	my ($self) = @_;

	unless (defined $self->layers()) {
		croak 'No "layers" hash reference with upstream layers provided';
	}

	$self->router(Router::Simple->new());
	my $layers = join('|', sort keys %{$self->layers()});
	my $formats = join('|', sort keys %format);
	$self->router()->connect(
		'/{layer:' . $layers . '}/{z:[0-9]+}/{x:[0-9]+}/{y:[0-9]+}.{format:' . $formats . '}'
	);

	$self->ua($self->ua() // HTTP::Tiny->new());

	$self->forward_headers($self->forward_headers() // [
		'Cache-Control',
		'Expires',
	]);

	return;
}


=head2 call

Method called to handle a request.

=cut

sub call {
	my ($self, $env) = @_;

	if (my $route = $self->router->match($env)) {
		my $tile_url = $self->layers()->{$route->{layer}};
		$tile_url =~ s{\{([^\}]+)\}}{$route->{$1}}gx;
		my $response = $self->ua()->get($tile_url);
		if ($response->{success}) {
			my $blob = $self->convert($response, $route->{format});
			return [200, [
				'Content-Type'   => $format{$route->{format}},
				'Content-Length' => length $blob,
				map {
					defined $response->{headers}->{lc $_}
						? ($_ => $response->{headers}->{lc $_})
						: ()
				} @{$self->forward_headers()},
			], [$blob]];
		}
		else {
			my $error = $response->{status} == 599
				? $response->{content}
				: $response->{status} . ' ' . $response->{reason};
			$env->{'psgi.errors'}->print(
				'Error fetching tile from ' . $tile_url . ': ' . $error . "\n"
			);
			return $self->error($response->{status}, $response->{reason});
		}
	}
	else {
		return $self->error(404, 'not found');
	}
}


=head2 convert

Convert the tile data from the response to grayscale in the given target image
format.

=head3 Parameters

This method expects positional parameters.

=over

=item response

The response from L<HTTP::Tiny|HTTP::Tiny>.

=item target_format

The target image format.

=back

=head3 Result

The image blob.

=cut

sub convert {
	my ($self, $response, $target_format) = @_;

	my $image = Image::Magick->new();
	$image->BlobToImage($response->{content});
	$image->Quantize(colorspace => 'gray');
	$image->Set(magick => $target_format);
	return $image->ImageToBlob();
}


=head2 error

Helper method to create error responses.

=head3 Parameters

This method expects positional parameters.

=over

=item status

Response status.

=item message

Error message to send in the body.

=back

=head3 Result

A L<PSGI|PSGI> response.

=cut

sub error {
	my ($self, $status, $message) = @_;

	return [$status, [
		'Content-Type' => 'text/plain; charset=UTF-8',
	], [$message]];
}


1;
