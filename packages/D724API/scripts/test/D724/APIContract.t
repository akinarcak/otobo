# --
# Copyright (C) 2026 Data Market Bilgi Hizmetleri A.S.
# SPDX-License-Identifier: GPL-3.0-only
# --
use v5.24;
use strict;
use warnings;
use Test2::V0;
use JSON::PP ();

my $Path = 'var/httpd/htdocs/d724/api/openapi-v1.json';
open my $Handle, '<:encoding(UTF-8)', $Path or die "Cannot read $Path: $!";
local $/;
my $Raw = <$Handle>;
close $Handle;
my $Contract = eval { JSON::PP::decode_json($Raw) };
ok( !$@ && ref $Contract eq 'HASH', 'OpenAPI contract is valid JSON' );
is( $Contract->{openapi}, '3.1.0', 'contract uses OpenAPI 3.1' );
is( $Contract->{servers}->[0]->{url}, '/otobo/api/v1', 'canonical API mount is declared' );
for my $PathKey (qw(/oauth/token /tickets /tickets/{ticket_id} /requests /requests/{request_id} /openapi.json)) {
    ok( $Contract->{paths}->{$PathKey}, "contract declares $PathKey" );
}
ok( $Contract->{paths}->{'/requests'}->{post}->{parameters}->[0]->{name} eq 'Idempotency-Key', 'request writes require idempotency header' );
ok( $Contract->{components}->{securitySchemes}->{bearerAuth}, 'bearer security scheme is declared' );
unlike( $Raw, qr{client_secret"\s*:\s*"[^\"]+"}i, 'contract contains no embedded client secret' );
unlike( $Raw, qr{access_token"\s*:\s*"[^\"]+"}i, 'contract contains no embedded bearer token' );

done_testing;
