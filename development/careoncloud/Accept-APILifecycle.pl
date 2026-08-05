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

my $BaseURL = $ARGV[0] // 'http://127.0.0.1:5000/careoncloud/api/v1';
die "Acceptance URL must use http(s)\n" if $BaseURL !~ m{\Ahttps?://}smx;
my $TenantID = 'careoncloud-demo';
my $RunID = time() . '-' . $$;
my $Admin = {
    ID => 'acceptance:api-lifecycle', TenantIDs => [$TenantID],
    RoleBindings => { $TenantID => ['tenant_admin'] },
};

local $Kernel::OM = Kernel::System::ObjectManager->new();
my $DB   = $Kernel::OM->Get('Kernel::System::DB');
my $Auth = $Kernel::OM->Get('Kernel::System::CareOnCloud::APIAuth');
$DB->Prepare(
    SQL => "SELECT id FROM careoncloud_catalog_item WHERE tenant_id = ? AND key_name = 'request-laptop' AND status = 'active'",
    Bind => [ \$TenantID ], Limit => 1,
);
my ($CatalogItemID) = $DB->FetchrowArray();
die "No active demo catalog item exists\n" if !$CatalogItemID;

my @Clients;
my %Secrets;
for my $Definition (
    [ requester => "lifecycle-requester-$RunID" ],
    [ tenant_admin => "lifecycle-admin-$RunID" ],
) {
    my ( $Role, $ClientID ) = @{$Definition};
    my $Created = $Auth->ClientCreate(
        Subject => $Admin, TenantID => $TenantID, Name => "Lifecycle $Role acceptance",
        Role => $Role, UserID => 1, TokenTTL => 120, RateLimit => 30, ClientID => $ClientID,
    );
    die "Client creation failed for $Role: $Created->{Error}\n" if !$Created->{Success};
    push @Clients, $ClientID;
    $Secrets{$Role} = $Created->{Data}->{ClientSecret};
}

my $HTTP = HTTP::Tiny->new( timeout => 20, verify_SSL => 1 );
my %Token;
my %Evidence;
my $Failure;

eval {
    for my $Role (qw(requester tenant_admin)) {
        my ($ClientID) = grep { $Role eq 'requester' ? /requester/ : /admin/ } @Clients;
        my $Form = 'grant_type=client_credentials&client_id=' . uri_escape_utf8($ClientID)
            . '&client_secret=' . uri_escape_utf8( $Secrets{$Role} );
        my $Response = $HTTP->post(
            "$BaseURL/oauth/token",
            { headers => { 'Content-Type' => 'application/x-www-form-urlencoded' }, content => $Form },
        );
        die "$Role token HTTP status $Response->{status}\n" if $Response->{status} != 200;
        my $JSON = JSON::PP::decode_json( $Response->{content} );
        $Token{$Role} = $JSON->{data}->{access_token};
        die "$Role token response invalid\n" if ( $Token{$Role} // q{} ) !~ m{\A[A-Za-z0-9]{64}\z}smx;
    }

    my $Payload = JSON::PP->new->canonical->encode({
        catalog_item_id => 0 + $CatalogItemID,
        requester_login => 'demo.customer',
        answers => {
            employee => 'API Lifecycle Acceptance', device_profile => 'standard',
            justification => "Lifecycle acceptance $RunID",
        },
    });
    my $Create = $HTTP->post(
        "$BaseURL/requests",
        { headers => {
            Authorization => "Bearer $Token{requester}", 'Content-Type' => 'application/json',
            'Idempotency-Key' => "api-lifecycle-$RunID",
        }, content => $Payload },
    );
    $Evidence{create_status} = 0 + $Create->{status};
    die "Request create HTTP status $Create->{status}\n" if $Create->{status} != 201;
    my $Request = JSON::PP::decode_json( $Create->{content} )->{data};
    my $RequestID = $Request->{id};
    my $ApprovalVersion = $Request->{approvals}->[0]->{version};
    my $TaskID = $Request->{tasks}->[0]->{id};
    die "Lifecycle request response invalid\n" if !$RequestID || !$ApprovalVersion || !$TaskID;

    my $ApprovalBody = JSON::PP->new->canonical->encode({
        decision => 'approved', expected_version => 0 + $ApprovalVersion,
        comment => 'Approved by lifecycle acceptance.',
    });
    my $RequesterDenied = $HTTP->post(
        "$BaseURL/requests/$RequestID/approval",
        { headers => { Authorization => "Bearer $Token{requester}", 'Content-Type' => 'application/json' }, content => $ApprovalBody },
    );
    $Evidence{requester_approval_status} = 0 + $RequesterDenied->{status};
    die "Requester approval was not forbidden\n" if $RequesterDenied->{status} != 403;

    my $Approval = $HTTP->post(
        "$BaseURL/requests/$RequestID/approval",
        { headers => { Authorization => "Bearer $Token{tenant_admin}", 'Content-Type' => 'application/json' }, content => $ApprovalBody },
    );
    $Evidence{approval_status} = 0 + $Approval->{status};
    die "Approval HTTP status $Approval->{status}\n" if $Approval->{status} != 200;
    my $Approved = JSON::PP::decode_json( $Approval->{content} )->{data};
    die "Approval did not enter fulfillment\n" if $Approved->{status} ne 'in_fulfillment';

    my $ApprovalReplay = $HTTP->post(
        "$BaseURL/requests/$RequestID/approval",
        { headers => { Authorization => "Bearer $Token{tenant_admin}", 'Content-Type' => 'application/json' }, content => $ApprovalBody },
    );
    $Evidence{approval_replay_status} = 0 + $ApprovalReplay->{status};
    die "Approval replay failed\n" if $ApprovalReplay->{status} != 200
        || lc( $ApprovalReplay->{headers}->{'idempotent-replayed'} // q{} ) ne 'true';

    my $TaskVersion = $Approved->{tasks}->[0]->{version};
    my $StartBody = JSON::PP->new->canonical->encode({
        status => 'in_progress', expected_version => 0 + $TaskVersion, comment => 'Acceptance work started.',
    });
    my $Started = $HTTP->request(
        'PATCH', "$BaseURL/tasks/$TaskID",
        { headers => { Authorization => "Bearer $Token{tenant_admin}", 'Content-Type' => 'application/json' }, content => $StartBody },
    );
    $Evidence{task_start_status} = 0 + $Started->{status};
    die "Task start HTTP status $Started->{status}\n" if $Started->{status} != 200;
    my $StartedData = JSON::PP::decode_json( $Started->{content} )->{data};

    my $StartReplay = $HTTP->request(
        'PATCH', "$BaseURL/tasks/$TaskID",
        { headers => { Authorization => "Bearer $Token{tenant_admin}", 'Content-Type' => 'application/json' }, content => $StartBody },
    );
    $Evidence{task_replay_status} = 0 + $StartReplay->{status};
    die "Task replay failed\n" if $StartReplay->{status} != 200
        || lc( $StartReplay->{headers}->{'idempotent-replayed'} // q{} ) ne 'true';

    my $CompleteBody = JSON::PP->new->canonical->encode({
        status => 'completed', expected_version => 0 + $StartedData->{tasks}->[0]->{version},
        comment => 'Acceptance work completed.',
    });
    my $Completed = $HTTP->request(
        'PATCH', "$BaseURL/tasks/$TaskID",
        { headers => { Authorization => "Bearer $Token{tenant_admin}", 'Content-Type' => 'application/json' }, content => $CompleteBody },
    );
    $Evidence{task_complete_status} = 0 + $Completed->{status};
    die "Task completion HTTP status $Completed->{status}\n" if $Completed->{status} != 200;
    my $CompletedData = JSON::PP::decode_json( $Completed->{content} )->{data};
    die "Request was not fulfilled\n" if $CompletedData->{status} ne 'fulfilled';

    my $Get = $HTTP->get(
        "$BaseURL/requests/$RequestID?requester_login=demo.customer",
        { headers => { Authorization => "Bearer $Token{requester}" } },
    );
    $Evidence{fulfilled_get_status} = 0 + $Get->{status};
    die "Fulfilled request GET failed\n" if $Get->{status} != 200
        || JSON::PP::decode_json( $Get->{content} )->{data}->{status} ne 'fulfilled';

    my $AdminClientID = $Clients[1];
    my @Values = ( $TenantID, $RequestID, "integration:$AdminClientID" );
    my @Bind = map { \$_ } @Values;
    $DB->Prepare(
        SQL => "SELECT action_name, actor_type FROM careoncloud_audit_event WHERE tenant_id = ? AND object_id IN (?, ?) AND actor_id = ? ORDER BY sequence_no",
        Bind => [ \$TenantID, \$RequestID, \$TaskID, \$Values[2] ],
    );
    my @Audit;
    while ( my @Row = $DB->FetchrowArray() ) { push @Audit, \@Row }
    die "Lifecycle audit evidence mismatch\n" if @Audit != 4
        || grep { $_->[1] ne 'integration' } @Audit;

    $Evidence{request_id} = 0 + $RequestID;
    $Evidence{task_id} = 0 + $TaskID;
    $Evidence{audit_events} = 0 + @Audit;
    $Evidence{final_status} = 'fulfilled';
    1;
} or $Failure = $@ || 'Unknown lifecycle acceptance failure';

for my $ClientID (@Clients) {
    my $Revoked = $Auth->ClientRevoke(
        Subject => $Admin, TenantID => $TenantID, ClientID => $ClientID, UserID => 1,
    );
    $Failure ||= "Client revocation failed: $Revoked->{Error}" if !$Revoked->{Success};
}
die $Failure if $Failure;

$Evidence{success} = JSON::PP::true;
$Evidence{tenant_id} = $TenantID;
say JSON::PP->new->canonical->encode(\%Evidence);
