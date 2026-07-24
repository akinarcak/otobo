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
my $RunID = time() . '-' . $$;
my $Admin = {
    ID => 'acceptance:webhook-subscription', TenantIDs => [$TenantID],
    RoleBindings => { $TenantID => ['tenant_admin'] },
};

local $Kernel::OM = Kernel::System::ObjectManager->new();
my $DB         = $Kernel::OM->Get('Kernel::System::DB');
my $Auth       = $Kernel::OM->Get('Kernel::System::D724::APIAuth');
my $Audit      = $Kernel::OM->Get('Kernel::System::D724::Audit');
my $Webhook    = $Kernel::OM->Get('Kernel::System::D724::Webhook');
my $Dispatcher = $Kernel::OM->Get('Kernel::System::D724::EscalationDispatcher');
my $JSON       = JSON::PP->new->canonical;

my @Clients;
my %Secrets;
for my $Definition (
    [ requester => "webhook-requester-$RunID" ],
    [ tenant_admin => "webhook-admin-$RunID" ],
) {
    my ( $Role, $ClientID ) = @{$Definition};
    my $Created = $Auth->ClientCreate(
        Subject => $Admin, TenantID => $TenantID, Name => "Webhook $Role acceptance",
        Role => $Role, UserID => 1, TokenTTL => 120, RateLimit => 40, ClientID => $ClientID,
    );
    die "Client creation failed for $Role: $Created->{Error}\n" if !$Created->{Success};
    push @Clients, $ClientID;
    $Secrets{$Role} = $Created->{Data}->{ClientSecret};
}

my $HTTP = HTTP::Tiny->new( timeout => 20, verify_SSL => 1 );
my ( %Token, %Evidence, $SubscriptionID, $Failure );
eval {
    my $Recovered = 0;
    while (1) {
        $DB->Prepare(
            SQL => "SELECT o.id, o.tenant_id, s.status, s.key_name FROM d724_escalation_outbox o LEFT JOIN d724_webhook_subscription s ON s.tenant_id = o.tenant_id AND CONCAT('webhooksub', s.id) = o.action_key WHERE o.status IN ('pending', 'retry') ORDER BY o.available_time, o.id",
            Limit => 1,
        );
        my ( $ExistingID, $ExistingTenant, $SubscriptionStatus, $SubscriptionKey ) = $DB->FetchrowArray();
        last if !$ExistingID;
        die "Competing ready outbox delivery prevents isolated acceptance\n"
            if $ExistingTenant ne $TenantID || ( $SubscriptionStatus // q{} ) ne 'inactive'
            || ( $SubscriptionKey // q{} ) !~ m{\Aacceptance-}smx;
        my $Recovery = $Dispatcher->Dispatch(
            At => '2099-01-01 00:00:00', Limit => 1, WorkerID => "webhook-recover-$RunID-$Recovered",
            Handlers => { webhook => sub {
                my ($Row) = @_;
                return { Success => 0, Error => 'WRONG_RECOVERY_DELIVERY' } if $Row->{ID} != $ExistingID;
                return { Success => 1, DeliveryRef => "acceptance-recovery:$ExistingID", ResponseCode => '202' };
            } },
        );
        die "Failed acceptance delivery recovery failed\n" if $Recovery->{Counts}->{Delivered} != 1;
        $Recovered++;
    }
    $Evidence{recovered_acceptance_deliveries} = $Recovered;

    for my $Index ( 0 .. 1 ) {
        my $Role = $Index ? 'tenant_admin' : 'requester';
        my $Form = 'grant_type=client_credentials&client_id=' . uri_escape_utf8( $Clients[$Index] )
            . '&client_secret=' . uri_escape_utf8( $Secrets{$Role} );
        my $Response = $HTTP->post(
            "$BaseURL/oauth/token",
            { headers => { 'Content-Type' => 'application/x-www-form-urlencoded' }, content => $Form },
        );
        die "$Role token HTTP status $Response->{status}\n" if $Response->{status} != 200;
        $Token{$Role} = JSON::PP::decode_json( $Response->{content} )->{data}->{access_token};
        die "$Role token response invalid\n" if ( $Token{$Role} // q{} ) !~ m{\A[A-Za-z0-9]{64}\z}smx;
    }

    my $CreateBody = $JSON->encode({
        key => "acceptance-$RunID", name => "Webhook acceptance $RunID",
        endpoint_key => 'lifecycle', event_patterns => ['request.*'],
    });
    my $RequesterDenied = $HTTP->post(
        "$BaseURL/webhook-subscriptions",
        { headers => { Authorization => "Bearer $Token{requester}", 'Content-Type' => 'application/json' }, content => $CreateBody },
    );
    $Evidence{requester_create_status} = 0 + $RequesterDenied->{status};
    die "Requester subscription create was not forbidden\n" if $RequesterDenied->{status} != 403;

    my $MissingEndpointBody = $JSON->encode({
        key => "missing-$RunID", name => 'Missing endpoint rejection',
        endpoint_key => 'not-configured', event_patterns => ['request.*'],
    });
    my $MissingEndpoint = $HTTP->post(
        "$BaseURL/webhook-subscriptions",
        { headers => { Authorization => "Bearer $Token{tenant_admin}", 'Content-Type' => 'application/json' }, content => $MissingEndpointBody },
    );
    $Evidence{missing_endpoint_status} = 0 + $MissingEndpoint->{status};
    die "Unconfigured endpoint was not rejected\n" if $MissingEndpoint->{status} != 422;

    my $Create = $HTTP->post(
        "$BaseURL/webhook-subscriptions",
        { headers => { Authorization => "Bearer $Token{tenant_admin}", 'Content-Type' => 'application/json' }, content => $CreateBody },
    );
    $Evidence{create_status} = 0 + $Create->{status};
    die "Subscription create HTTP status $Create->{status}: $Create->{content}\n" if $Create->{status} != 201;
    my $Subscription = JSON::PP::decode_json( $Create->{content} )->{data};
    $SubscriptionID = $Subscription->{id};
    die "Subscription response invalid\n" if !$SubscriptionID || $Subscription->{tenant_id} ne $TenantID;

    my $List = $HTTP->get(
        "$BaseURL/webhook-subscriptions",
        { headers => { Authorization => "Bearer $Token{tenant_admin}" } },
    );
    $Evidence{list_status} = 0 + $List->{status};
    die "Subscription list HTTP status $List->{status}\n" if $List->{status} != 200;
    my @Listed = @{ JSON::PP::decode_json( $List->{content} )->{data} // [] };
    die "Created subscription $SubscriptionID missing from tenant list: $List->{content}\n"
        if !grep { $_->{id} == $SubscriptionID } @Listed;
    die "Cross-tenant subscription leaked\n" if grep { $_->{tenant_id} ne $TenantID } @Listed;

    my $Get = $HTTP->get(
        "$BaseURL/webhook-subscriptions/$SubscriptionID",
        { headers => { Authorization => "Bearer $Token{tenant_admin}" } },
    );
    $Evidence{get_status} = 0 + $Get->{status};
    die "Subscription get HTTP status $Get->{status}\n" if $Get->{status} != 200;

    my $Event = $Audit->Record(
        TenantID => $TenantID, ActorType => 'integration', ActorID => "integration:$Clients[1]",
        Action => 'request.acceptance_emitted', ObjectType => 'request', ObjectID => "accept-$RunID",
        CorrelationID => "WH-ACCEPT-$RunID", DedupeKey => "webhook-acceptance:$RunID",
        FromState => 'pending', ToState => 'accepted', Outcome => 'success',
        Details => { acceptance_run => $RunID },
    );
    die "Lifecycle audit event failed: $Event->{Error}\n" if !$Event->{Success};
    my $Scanned = $Webhook->Scan( Limit => 100 );
    die "Webhook scan failed\n" if !$Scanned->{Success};

    my $ActionKey = 'webhooksub' . $SubscriptionID;
    $DB->Prepare(
        SQL => "SELECT id, status, payload_json FROM d724_escalation_outbox WHERE tenant_id = ? AND commitment_id = 0 AND action_key = ? ORDER BY id DESC",
        Bind => [ \$TenantID, \$ActionKey ], Limit => 1,
    );
    my ( $OutboxID, $OutboxStatus, $PayloadJSON ) = $DB->FetchrowArray();
    die "Shared outbox delivery missing\n" if !$OutboxID || $OutboxStatus ne 'pending';
    my $Payload = JSON::PP::decode_json($PayloadJSON);
    die "Normalized delivery payload mismatch\n"
        if $Payload->{Event}->{Action} ne 'request.acceptance_emitted'
        || $Payload->{SubscriptionID} != $SubscriptionID;

    $DB->Prepare(SQL => "SELECT COUNT(*) FROM d724_escalation_outbox WHERE status IN ('pending', 'retry')");
    my ($ReadyCount) = $DB->FetchrowArray();
    die "Competing ready outbox deliveries prevent isolated acceptance\n" if $ReadyCount != 1;
    my $Delivered = $Dispatcher->Dispatch(
        At => '2099-01-01 00:00:00', Limit => 1, WorkerID => "webhook-accept-$RunID",
        Handlers => { webhook => sub {
            my ($Row) = @_;
            return { Success => 0, Error => 'WRONG_DELIVERY' }
                if $Row->{ID} != $OutboxID || $Row->{TenantID} ne $TenantID;
            return { Success => 1, DeliveryRef => "acceptance:$OutboxID", ResponseCode => '202' };
        } },
    );
    die "Shared dispatcher did not deliver acceptance event\n" if $Delivered->{Counts}->{Delivered} != 1;

    my $DisableBody = $JSON->encode({ expected_version => 1, status => 'inactive' });
    my $Disabled = $HTTP->request(
        'PATCH', "$BaseURL/webhook-subscriptions/$SubscriptionID",
        { headers => { Authorization => "Bearer $Token{tenant_admin}", 'Content-Type' => 'application/json' }, content => $DisableBody },
    );
    $Evidence{disable_status} = 0 + $Disabled->{status};
    die "Subscription disable HTTP status $Disabled->{status}\n" if $Disabled->{status} != 200;
    my $DisabledData = JSON::PP::decode_json( $Disabled->{content} )->{data};
    die "Subscription was not disabled\n" if $DisabledData->{status} ne 'inactive';

    my $Stale = $HTTP->request(
        'PATCH', "$BaseURL/webhook-subscriptions/$SubscriptionID",
        { headers => { Authorization => "Bearer $Token{tenant_admin}", 'Content-Type' => 'application/json' }, content => $DisableBody },
    );
    $Evidence{stale_update_status} = 0 + $Stale->{status};
    die "Stale subscription update did not conflict\n" if $Stale->{status} != 409;

    $Evidence{subscription_id} = 0 + $SubscriptionID;
    $Evidence{audit_sequence} = 0 + $Event->{Data}->{Sequence};
    $Evidence{outbox_id} = 0 + $OutboxID;
    $Evidence{delivery_status} = 'delivered';
    1;
} or $Failure = $@ || 'Unknown webhook subscription acceptance failure';

if ($SubscriptionID) {
    my $Current = $Webhook->SubscriptionGet(
        Subject => $Admin, TenantID => $TenantID, SubscriptionID => $SubscriptionID,
    );
    if ( $Current->{Success} && $Current->{Data}->{Status} eq 'active' ) {
        my $Disabled = $Webhook->SubscriptionUpdate(
            Subject => $Admin, TenantID => $TenantID, SubscriptionID => $SubscriptionID,
            ExpectedVersion => $Current->{Data}->{Version}, Status => 'inactive',
        );
        $Failure ||= "Acceptance subscription cleanup failed: $Disabled->{Error}" if !$Disabled->{Success};
    }
}
for my $ClientID (@Clients) {
    my $Revoked = $Auth->ClientRevoke(
        Subject => $Admin, TenantID => $TenantID, ClientID => $ClientID, UserID => 1,
    );
    $Failure ||= "Client revocation failed: $Revoked->{Error}" if !$Revoked->{Success};
}
die $Failure if $Failure;

$Evidence{success} = JSON::PP::true;
$Evidence{tenant_id} = $TenantID;
say $JSON->encode(\%Evidence);
