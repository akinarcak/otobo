#!/usr/bin/env perl
# --
# Copyright (C) 2026 Data Market Bilgi Hizmetleri A.S.
# SPDX-License-Identifier: GPL-3.0-only
# --
use v5.24;
use strict;
use warnings;
use HTTP::Tiny ();
use JSON::PP ();
use URI::Escape qw(uri_escape_utf8);
use Kernel::System::ObjectManager;

my $BaseURL = $ARGV[0] // 'http://127.0.0.1:5000/otobo/api/v1';
die "Acceptance URL must use http(s)\n" if $BaseURL !~ m{\Ahttps?://}smx;
my $TenantID = 'd724-demo';
my $ClientID = 'accept-' . time() . '-' . $$;
my $Admin = {
    ID => 'acceptance:api', TenantIDs => [$TenantID],
    RoleBindings => { $TenantID => ['tenant_admin'] },
};

local $Kernel::OM = Kernel::System::ObjectManager->new();
my $DB   = $Kernel::OM->Get('Kernel::System::DB');
my $Auth = $Kernel::OM->Get('Kernel::System::D724::APIAuth');
$DB->Prepare(
    SQL => "SELECT ticket_id FROM d724_ticket_scope WHERE tenant_id = ? AND status = 'active' ORDER BY ticket_id ASC",
    Bind => [ \$TenantID ], Limit => 1,
);
my ($TicketID) = $DB->FetchrowArray();
die "No active demo ticket exists\n" if !$TicketID;
$DB->Prepare(
    SQL => "SELECT id FROM d724_catalog_item WHERE tenant_id = ? AND key_name = 'request-laptop' AND status = 'active'",
    Bind => [ \$TenantID ], Limit => 1,
);
my ($CatalogItemID) = $DB->FetchrowArray();
die "No active demo catalog item exists\n" if !$CatalogItemID;

my $Created = $Auth->ClientCreate(
    Subject => $Admin, TenantID => $TenantID, Name => 'HTTP acceptance client',
    Role => 'requester', UserID => 1, TokenTTL => 60, RateLimit => 20, ClientID => $ClientID,
);
die "Client creation failed: $Created->{Error}\n" if !$Created->{Success};

my $HTTP = HTTP::Tiny->new( timeout => 15, verify_SSL => 1 );
my ( $Token, $Failure );
my %Evidence;
eval {
    my $Form = join '&', map { uri_escape_utf8($_) . '=' . uri_escape_utf8( $Created->{Data}->{$_} // q{} ) }
        qw(ClientID ClientSecret);
    $Form =~ s/ClientID=/client_id=/;
    $Form =~ s/ClientSecret=/client_secret=/;
    $Form = 'grant_type=client_credentials&' . $Form;
    my $TokenResponse = $HTTP->post(
        "$BaseURL/oauth/token",
        { headers => { 'Content-Type' => 'application/x-www-form-urlencoded' }, content => $Form },
    );
    $Evidence{token_status} = 0 + $TokenResponse->{status};
    die "Token HTTP status $TokenResponse->{status}\n" if $TokenResponse->{status} != 200;
    my $TokenJSON = JSON::PP::decode_json( $TokenResponse->{content} );
    $Token = $TokenJSON->{data}->{access_token};
    die "Token response invalid\n" if ( $Token // q{} ) !~ m{\A[a-zA-Z0-9]{64}\z}smx;

    my $Headers = { Authorization => "Bearer $Token" };
    my $ListResponse = $HTTP->get( "$BaseURL/tickets?limit=100", { headers => $Headers } );
    $Evidence{list_status} = 0 + $ListResponse->{status};
    die "List HTTP status $ListResponse->{status}\n" if $ListResponse->{status} != 200;
    my $ListJSON = JSON::PP::decode_json( $ListResponse->{content} );
    my @Items = @{ $ListJSON->{data}->{items} // [] };
    die "Demo ticket missing from list\n" if !grep { $_->{id} == $TicketID } @Items;
    die "Cross-tenant item leaked\n" if grep { ( $_->{tenant_id} // q{} ) ne $TenantID } @Items;
    $Evidence{list_count} = 0 + @Items;
    $Evidence{tenant_isolated} = JSON::PP::true;

    my $GetResponse = $HTTP->get( "$BaseURL/tickets/$TicketID", { headers => $Headers } );
    $Evidence{get_status} = 0 + $GetResponse->{status};
    die "Get HTTP status $GetResponse->{status}\n" if $GetResponse->{status} != 200;
    my $GetJSON = JSON::PP::decode_json( $GetResponse->{content} );
    die "Get returned wrong ticket\n" if $GetJSON->{data}->{id} != $TicketID;

    my $HiddenResponse = $HTTP->get( "$BaseURL/tickets/999999999", { headers => $Headers } );
    $Evidence{hidden_status} = 0 + $HiddenResponse->{status};
    die "Unknown ticket was not hidden\n" if $HiddenResponse->{status} != 404;

    my $RequestPayload = JSON::PP->new->canonical->encode({
        catalog_item_id => 0 + $CatalogItemID,
        requester_login => 'demo.customer',
        answers => {
            employee => 'API Acceptance User', device_profile => 'standard',
            justification => 'Canonical API idempotency acceptance',
        },
    });
    my $IdempotencyKey = 'api-accept-d724-demo-v1-0001';
    my $WriteHeaders = {
        %{$Headers}, 'Content-Type' => 'application/json',
        'Idempotency-Key' => $IdempotencyKey,
    };
    my $CreateResponse = $HTTP->post(
        "$BaseURL/requests", { headers => $WriteHeaders, content => $RequestPayload },
    );
    $Evidence{request_create_status} = 0 + $CreateResponse->{status};
    die "Request create HTTP status $CreateResponse->{status}\n"
        if $CreateResponse->{status} != 201 && $CreateResponse->{status} != 200;
    my $CreateJSON = JSON::PP::decode_json( $CreateResponse->{content} );
    my $RequestID = $CreateJSON->{data}->{id};
    die "Request create response invalid\n" if !$RequestID;

    my $ReplayResponse = $HTTP->post(
        "$BaseURL/requests", { headers => $WriteHeaders, content => $RequestPayload },
    );
    $Evidence{request_replay_status} = 0 + $ReplayResponse->{status};
    die "Request replay HTTP status $ReplayResponse->{status}\n" if $ReplayResponse->{status} != 200;
    my $ReplayJSON = JSON::PP::decode_json( $ReplayResponse->{content} );
    die "Idempotent replay returned a different request\n" if $ReplayJSON->{data}->{id} != $RequestID;
    die "Idempotent replay header missing\n"
        if lc( $ReplayResponse->{headers}->{'idempotent-replayed'} // q{} ) ne 'true';

    my $ConflictPayload = JSON::PP->new->canonical->encode({
        catalog_item_id => 0 + $CatalogItemID,
        requester_login => 'demo.customer',
        answers => {
            employee => 'API Acceptance User', device_profile => 'standard',
            justification => 'Different payload must conflict',
        },
    });
    my $ConflictResponse = $HTTP->post(
        "$BaseURL/requests", { headers => $WriteHeaders, content => $ConflictPayload },
    );
    $Evidence{request_conflict_status} = 0 + $ConflictResponse->{status};
    die "Idempotency conflict HTTP status $ConflictResponse->{status}\n" if $ConflictResponse->{status} != 409;

    my $RequestGet = $HTTP->get(
        "$BaseURL/requests/$RequestID?requester_login=demo.customer", { headers => $Headers },
    );
    $Evidence{request_get_status} = 0 + $RequestGet->{status};
    die "Request get HTTP status $RequestGet->{status}\n" if $RequestGet->{status} != 200;
    my $RequestJSON = JSON::PP::decode_json( $RequestGet->{content} );
    die "Request get returned wrong tenant\n" if $RequestJSON->{data}->{tenant_id} ne $TenantID;
    $Evidence{request_id} = 0 + $RequestID;

    my $OpenAPI = $HTTP->get("$BaseURL/openapi.json");
    $Evidence{openapi_status} = 0 + $OpenAPI->{status};
    die "OpenAPI HTTP status $OpenAPI->{status}\n" if $OpenAPI->{status} != 200;
    my $OpenAPIJSON = JSON::PP::decode_json( $OpenAPI->{content} );
    die "OpenAPI version mismatch\n" if $OpenAPIJSON->{openapi} ne '3.1.0';

    my $OldSecret = $Created->{Data}->{ClientSecret};
    my $OldToken  = $Token;
    my $Rotation = $Auth->ClientSecretRotate(
        Subject => $Admin, TenantID => $TenantID, ClientID => $ClientID,
        UserID => 1, ExpectedVersion => 1,
    );
    die "Client secret rotation failed: $Rotation->{Error}\n" if !$Rotation->{Success};
    $Evidence{rotation_version} = 0 + $Rotation->{Data}->{Version};
    my $OldTokenResponse = $HTTP->get(
        "$BaseURL/tickets?limit=1", { headers => { Authorization => "Bearer $OldToken" } },
    );
    $Evidence{rotated_old_token_status} = 0 + $OldTokenResponse->{status};
    die "Old token survived rotation\n" if $OldTokenResponse->{status} != 401;

    my $OldForm = 'grant_type=client_credentials&client_id=' . uri_escape_utf8($ClientID)
        . '&client_secret=' . uri_escape_utf8($OldSecret);
    my $OldSecretResponse = $HTTP->post(
        "$BaseURL/oauth/token",
        { headers => { 'Content-Type' => 'application/x-www-form-urlencoded' }, content => $OldForm },
    );
    $Evidence{rotated_old_secret_status} = 0 + $OldSecretResponse->{status};
    die "Old secret survived rotation\n" if $OldSecretResponse->{status} != 401;

    my $NewForm = 'grant_type=client_credentials&client_id=' . uri_escape_utf8($ClientID)
        . '&client_secret=' . uri_escape_utf8( $Rotation->{Data}->{ClientSecret} );
    my $NewSecretResponse = $HTTP->post(
        "$BaseURL/oauth/token",
        { headers => { 'Content-Type' => 'application/x-www-form-urlencoded' }, content => $NewForm },
    );
    $Evidence{rotated_new_secret_status} = 0 + $NewSecretResponse->{status};
    die "New secret token HTTP status $NewSecretResponse->{status}\n" if $NewSecretResponse->{status} != 200;
    my $NewTokenJSON = JSON::PP::decode_json( $NewSecretResponse->{content} );
    $Token = $NewTokenJSON->{data}->{access_token};
    die "New secret token response invalid\n" if ( $Token // q{} ) !~ m{\A[a-zA-Z0-9]{64}\z}smx;
    my $NewTokenList = $HTTP->get(
        "$BaseURL/tickets?limit=1", { headers => { Authorization => "Bearer $Token" } },
    );
    $Evidence{rotated_new_token_status} = 0 + $NewTokenList->{status};
    die "New token is unusable\n" if $NewTokenList->{status} != 200;
    1;
} or $Failure = $@ || 'Unknown acceptance failure';

my $Revoked = $Auth->ClientRevoke(
    Subject => $Admin, TenantID => $TenantID, ClientID => $ClientID, UserID => 1,
);
$Failure ||= "Client revocation failed: $Revoked->{Error}" if !$Revoked->{Success};
if ( $Token && $Revoked->{Success} ) {
    my $After = $HTTP->get(
        "$BaseURL/tickets?limit=1",
        { headers => { Authorization => "Bearer $Token" } },
    );
    $Evidence{revoked_token_status} = 0 + $After->{status};
    $Failure ||= "Revoked token HTTP status $After->{status}" if $After->{status} != 401;
}
die $Failure if $Failure;

$Evidence{success} = JSON::PP::true;
$Evidence{tenant_id} = $TenantID;
$Evidence{ticket_id} = 0 + $TicketID;
say JSON::PP->new->canonical->encode(\%Evidence);
