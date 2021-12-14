# SYNOPSIS

In some e.g. `app.psgi`:

        use strict;
        use warnings;

        use App::TileProxy::Grayscale;

        my $app = App::TileProxy::Grayscale->new({
                layers => {
                        osm => 'https://some.tile.server/base/{z}/{x}/{y}.png',
                },
        })->to_app();

Run application with e.g. [Starman](https://metacpan.org/pod/Starman):

        starman --port 8080 app.psgi

Access tiles:

        http://localhost:8080/osm/{z}/{x}/{y}.png

# DESCRIPTION

This [Plack](https://metacpan.org/pod/Plack)/[PSGI](https://metacpan.org/pod/PSGI) application acts as a reverse proxy for tile
servers which does a conversion of the served tiles to grayscale.

## Dependencies

On Debian, the following command installs the required packages:

        apt install libplack-perl libimage-magick-perl librouter-simple-perl

[Starman](https://metacpan.org/pod/Starman) can be installed as follows, but is only required when
running the application with it:

        apt install starman

# PARAMETERS

- layers

    Hash reference with layers to offer. The key will be part of the tile URLs while
    the key is a regular tile URL template.

- forward\_headers

    Array reference with response headers from the upstream tile server that should
    be forwarded. Defaults to `Cache-Control` and `Expires` headers.

- ua

    [HTTP::Tiny](https://metacpan.org/pod/HTTP%3A%3ATiny) instance to use as user agent for tile retrieval.

# METHODS

## prepare\_app

Hook called by [Plack::Component](https://metacpan.org/pod/Plack%3A%3AComponent) to prepare the application.

## call

Method called to handle a request.

## convert

Convert the tile data from the response to grayscale in the given target image
format.

### Parameters

This method expects positional parameters.

- response

    The response from [HTTP::Tiny](https://metacpan.org/pod/HTTP%3A%3ATiny).

- target\_format

    The target image format.

### Result

The image blob.

## error

Helper method to create error responses.

### Parameters

This method expects positional parameters.

- status

    Response status.

- message

    Error message to send in the body.

### Result

A [PSGI](https://metacpan.org/pod/PSGI) response.
