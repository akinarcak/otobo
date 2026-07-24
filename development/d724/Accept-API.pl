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

my $BaseURL = $ARGV[0] // 'http://127.0.0.1:5000/otobo/public.pl?Action=PublicD724API';
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
        "$BaseURL&Route=token",
        { headers => { 'Content-Type' => 'application/x-www-form-urlencoded' }, content => $Form },
    );
    $Evidence{token_status} = 0 + $TokenResponse->{status};
    die "Token HTTP status $TokenResponse->{status}\n" if $TokenResponse->{status} != 200;
    my $TokenJSON = JSON::PP::decode_json( $TokenResponse->{content} );
    $Token = $TokenJSON->{data}->{access_token};
    die "Token response invalid\n" if ( $Token // q{} ) !~ m{\A[a-zA-Z0-9]{64}\z}smx;

    my $Headers = { Authorization => "Bearer $Token" };
    my $ListResponse = $HTTP->get( "$BaseURL&Route=tickets&limit=100", { headers => $Headers } );
    $Evidence{list_status} = 0 + $ListResponse->{status};
    die "List HTTP status $ListResponse->{status}\n" if $ListResponse->{status} != 200;
    my $ListJSON = JSON::PP::decode_json( $ListResponse->{content} );
    my @Items = @{ $ListJSON->{data}->{items} // [] };
    die "Demo ticket missing from list\n" if !grep { $_->{id} == $TicketID } @Items;
    die "Cross-tenant item leaked\n" if grep { ( $_->{tenant_id} // q{} ) ne $TenantID } @Items;
    $Evidence{list_count} = 0 + @Items;
    $Evidence{tenant_isolated} = JSON::PP::true;

    my $GetResponse = $HTTP->get( "$BaseURL&Route=ticket&ticket_id=$TicketID", { headers => $Headers } );
    $Evidence{get_status} = 0 + $GetResponse->{status};
    die "Get HTTP status $GetResponse->{status}\n" if $GetResponse->{status} != 200;
    my $GetJSON = JSON::PP::decode_json( $GetResponse->{content} );
    die "Get returned wrong ticket\n" if $GetJSON->{data}->{id} != $TicketID;

    my $HiddenResponse = $HTTP->get( "$BaseURL&Route=ticket&ticket_id=999999999", { headers => $Headers } );
    $Evidence{hidden_status} = 0 + $HiddenResponse->{status};
    die "Unknown ticket was not hidden\n" if $HiddenResponse->{status} != 404;
    1;
} or $Failure = $@ || 'Unknown acceptance failure';

my $Revoked = $Auth->ClientRevoke(
    Subject => $Admin, TenantID => $TenantID, ClientID => $ClientID, UserID => 1,
);
$Failure ||= "Client revocation failed: $Revoked->{Error}" if !$Revoked->{Success};
if ( $Token && $Revoked->{Success} ) {
    my $After = $HTTP->get(
        "$BaseURL&Route=tickets&limit=1",
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
