#!/usr/bin/env perl
# --
# Copyright (C) 2026 Data Market Bilgi Hizmetleri A.S.
# SPDX-License-Identifier: GPL-3.0-only
# --
use v5.24;
use strict;
use warnings;
use JSON::PP ();
use Kernel::System::ObjectManager;

my $TenantID = $ARGV[0] // 'd724-demo';
my $RunID = time() . '-' . $$;
my $ActionKey = "acceptance-replay-$RunID";
my $Subject = {
    ID => 'agent:1', TenantIDs => [$TenantID],
    RoleBindings => { $TenantID => ['tenant_admin'] },
};

local $Kernel::OM = Kernel::System::ObjectManager->new();
my $DB = $Kernel::OM->Get('Kernel::System::DB');
my $JSON = $Kernel::OM->Get('Kernel::System::JSON');
my $Dispatcher = $Kernel::OM->Get('Kernel::System::D724::EscalationDispatcher');
my $Now = $Kernel::OM->Create('Kernel::System::DateTime');
$Now->ToTimeZone( TimeZone => 'UTC' );
my $At = $Now->ToString();

$DB->Prepare(
    SQL => 'SELECT e.commitment_id, e.id FROM d724_commitment_event e INNER JOIN d724_commitment_instance i ON i.id = e.commitment_id AND i.tenant_id = e.tenant_id WHERE e.tenant_id = ? ORDER BY e.id DESC',
    Bind => [ \$TenantID ], Limit => 1,
);
my ( $CommitmentID, $EventID ) = $DB->FetchrowArray();
die "No demo commitment event exists\n" if !$CommitmentID || !$EventID;

my $Payload = $JSON->Encode(
    Data => {
        TenantID => $TenantID, RequestID => 0, Target => 'acceptance-endpoint',
        Trigger => 'acceptance', ObjectiveKey => 'acceptance', DueTime => $At,
    },
    SortKeys => 1,
);
my @Values = (
    $TenantID, $CommitmentID, $EventID, $ActionKey, 'webhook', $Payload,
    'dead', 3, 3, 0, $At, 'ACCEPTANCE_DEAD_LETTER',
);
my @Bind = map { \$_ } @Values;
die "Acceptance outbox insert failed\n" if !$DB->Do(
    SQL => 'INSERT INTO d724_escalation_outbox (tenant_id, commitment_id, commitment_event_id, action_key, action_type, payload_json, status, attempt_count, lifetime_attempt_count, replay_count, available_time, last_error, create_time, change_time) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, current_timestamp, current_timestamp)',
    Bind => \@Bind,
);
$DB->Prepare(
    SQL => 'SELECT id FROM d724_escalation_outbox WHERE tenant_id = ? AND commitment_event_id = ? AND action_key = ?',
    Bind => [ \$TenantID, \$EventID, \$ActionKey ], Limit => 1,
);
my ($OutboxID) = $DB->FetchrowArray();
die "Acceptance outbox lookup failed\n" if !$OutboxID;

my %Evidence = ( tenant_id => $TenantID, outbox_id => 0 + $OutboxID );
my $CrossTenant = $Dispatcher->Replay(
    Subject => { ID => 'agent:999999', TenantIDs => ['acceptance-other'], RoleBindings => { 'acceptance-other' => ['tenant_admin'] } },
    TenantID => $TenantID, OutboxID => $OutboxID, ExpectedAttemptCount => 3, At => $At,
);
$Evidence{cross_tenant_error} = $CrossTenant->{Error} // q{};
die "Cross-tenant replay did not fail closed\n" if ( $CrossTenant->{Error} // q{} ) ne 'FORBIDDEN';

my $Stale = $Dispatcher->Replay(
    Subject => $Subject, TenantID => $TenantID, OutboxID => $OutboxID,
    ExpectedAttemptCount => 2, At => $At,
);
$Evidence{stale_error} = $Stale->{Error} // q{};
die "Stale replay did not conflict\n" if ( $Stale->{Error} // q{} ) ne 'VERSION_CONFLICT';

my $Replay = $Dispatcher->Replay(
    Subject => $Subject, TenantID => $TenantID, OutboxID => $OutboxID,
    ExpectedAttemptCount => 3, At => $At,
);
die "Dead-letter replay failed: $Replay->{Error}\n" if !$Replay->{Success};
$Evidence{replay_count} = 0 + $Replay->{Data}->{ReplayCount};
$Evidence{replay_status} = $Replay->{Data}->{Status};

my $Dispatch = $Dispatcher->Dispatch(
    At => $At, Limit => 1, WorkerID => "acceptance-replay-$$",
    Handlers => { webhook => sub {
        my ($Row) = @_;
        die "Dispatcher claimed another tenant or delivery\n"
            if $Row->{TenantID} ne $TenantID || $Row->{ID} != $OutboxID;
        return { Success => 1, DeliveryRef => "acceptance:$OutboxID", ResponseCode => '202' };
    } },
);
die "Replay dispatch failed\n" if !$Dispatch->{Success} || $Dispatch->{Counts}->{Delivered} != 1;

$DB->Prepare(
    SQL => 'SELECT status, attempt_count, lifetime_attempt_count, replay_count, delivery_ref, response_code FROM d724_escalation_outbox WHERE tenant_id = ? AND id = ?',
    Bind => [ \$TenantID, \$OutboxID ], Limit => 1,
);
my ( $Status, $Attempts, $Lifetime, $ReplayCount, $DeliveryRef, $ResponseCode ) = $DB->FetchrowArray();
die "Delivered replay evidence mismatch\n"
    if $Status ne 'delivered' || $Attempts != 1 || $Lifetime != 4 || $ReplayCount != 1
    || $DeliveryRef ne "acceptance:$OutboxID" || $ResponseCode ne '202';

my $Audit = $Kernel::OM->Get('Kernel::System::D724::Audit')->List(
    Subject => $Subject, TenantID => $TenantID, ObjectType => 'escalation_outbox', ObjectID => $OutboxID, Limit => 10,
);
die "Replay audit lookup failed\n" if !$Audit->{Success};
my @ReplayAudit = grep { $_->{Action} eq 'commitment.escalation_replayed' } @{ $Audit->{Data} };
die "Replay audit evidence mismatch\n" if @ReplayAudit != 1 || $ReplayAudit[0]->{FromState} ne 'dead' || $ReplayAudit[0]->{ToState} ne 'retry';

my $Again = $Dispatcher->Replay(
    Subject => $Subject, TenantID => $TenantID, OutboxID => $OutboxID,
    ExpectedAttemptCount => 1, At => $At,
);
$Evidence{terminal_replay_error} = $Again->{Error} // q{};
die "Delivered record was replayed again\n" if ( $Again->{Error} // q{} ) ne 'REPLAY_STATE_INVALID';

$Evidence{final_status} = $Status;
$Evidence{attempt_count} = 0 + $Attempts;
$Evidence{lifetime_attempt_count} = 0 + $Lifetime;
$Evidence{audit_events} = 0 + @ReplayAudit;
$Evidence{success} = JSON::PP::true;
say JSON::PP->new->canonical->encode(\%Evidence);
