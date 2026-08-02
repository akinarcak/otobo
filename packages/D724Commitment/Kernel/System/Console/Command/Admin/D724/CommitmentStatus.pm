# --
# CareOnCloud ESM enterprise service management platform.
# Copyright (C) 2026 Data Market Bilgi Hizmetleri A.S.
# SPDX-License-Identifier: GPL-3.0-only
# --

package Kernel::System::Console::Command::Admin::D724::CommitmentStatus;

use v5.24;
use strict;
use warnings;
use parent qw(Kernel::System::Console::BaseCommand);

our $VERSION = '0.5.0';

our @ObjectDependencies = ('Kernel::System::DB', 'Kernel::System::JSON');

sub Configure {
    my ($Self) = @_;
    $Self->Description('Validate the D724 commitment schema and print operational counts.');
    $Self->AddOption( Name => 'json', Description => 'Print JSON.', Required => 0, HasValue => 0 );
    return;
}

sub Run {
    my ($Self) = @_;
    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');
    my %Existing = map { $_ => 1 } $DBObject->ListTables();
    my %Tables = map { $_ => $Existing{$_} ? 1 : 0 } qw(d724_commitment_policy d724_commitment_objective d724_commitment_instance d724_commitment_event d724_escalation_outbox);
    my %Counts = (
        Policies => 0, Objectives => 0, Active => 0, Breached => 0,
        PendingEscalations => 0, RetryEscalations => 0, ProcessingEscalations => 0,
        DeliveredEscalations => 0, DeadEscalations => 0, DeliveredWebhooks => 0,
        DeadWebhooks => 0, LifetimeAttempts => 0, ReplayedEscalations => 0,
        InvalidAutomationCommitments => 0, InvalidAutomationDeliveries => 0,
    );
    if ( $Tables{d724_commitment_policy} ) {
        $DBObject->Prepare( SQL => "SELECT COUNT(*) FROM d724_commitment_policy WHERE status = 'active'" );
        ($Counts{Policies}) = $DBObject->FetchrowArray();
    }
    if ( $Tables{d724_commitment_objective} ) {
        $DBObject->Prepare( SQL => 'SELECT COUNT(*) FROM d724_commitment_objective' );
        ($Counts{Objectives}) = $DBObject->FetchrowArray();
    }
    if ( $Tables{d724_commitment_instance} ) {
        $DBObject->Prepare( SQL => "SELECT COUNT(*) FROM d724_commitment_instance WHERE status IN ('running', 'warning', 'paused')" );
        ($Counts{Active}) = $DBObject->FetchrowArray();
        $DBObject->Prepare( SQL => "SELECT COUNT(*) FROM d724_commitment_instance WHERE status = 'breached'" );
        ($Counts{Breached}) = $DBObject->FetchrowArray();
        $DBObject->Prepare( SQL => "SELECT COUNT(*) FROM d724_commitment_instance i LEFT JOIN d724_tenant t ON t.key_name = i.tenant_id AND t.status = 'active' WHERE i.status IN ('running','warning') AND t.key_name IS NULL" );
        ($Counts{InvalidAutomationCommitments}) = $DBObject->FetchrowArray();
    }
    if ( $Tables{d724_escalation_outbox} ) {
        $DBObject->Prepare( SQL => "SELECT COUNT(*) FROM d724_escalation_outbox WHERE status IN ('pending','retry','processing')" );
        ($Counts{PendingEscalations}) = $DBObject->FetchrowArray();
        $DBObject->Prepare( SQL => "SELECT COUNT(*) FROM d724_escalation_outbox WHERE status = 'dead'" );
        ($Counts{DeadEscalations}) = $DBObject->FetchrowArray();
        $DBObject->Prepare( SQL => "SELECT COUNT(*) FROM d724_escalation_outbox WHERE status = 'retry'" );
        ($Counts{RetryEscalations}) = $DBObject->FetchrowArray();
        $DBObject->Prepare( SQL => "SELECT COUNT(*) FROM d724_escalation_outbox WHERE status = 'processing'" );
        ($Counts{ProcessingEscalations}) = $DBObject->FetchrowArray();
        $DBObject->Prepare( SQL => "SELECT COUNT(*) FROM d724_escalation_outbox WHERE status = 'delivered'" );
        ($Counts{DeliveredEscalations}) = $DBObject->FetchrowArray();
        $DBObject->Prepare( SQL => "SELECT COUNT(*) FROM d724_escalation_outbox WHERE action_type = 'webhook' AND status = 'delivered'" );
        ($Counts{DeliveredWebhooks}) = $DBObject->FetchrowArray();
        $DBObject->Prepare( SQL => "SELECT COUNT(*) FROM d724_escalation_outbox WHERE action_type = 'webhook' AND status = 'dead'" );
        ($Counts{DeadWebhooks}) = $DBObject->FetchrowArray();
        $DBObject->Prepare( SQL => 'SELECT COALESCE(SUM(lifetime_attempt_count), 0), COALESCE(SUM(replay_count), 0) FROM d724_escalation_outbox' );
        ( $Counts{LifetimeAttempts}, $Counts{ReplayedEscalations} ) = $DBObject->FetchrowArray();
        $DBObject->Prepare( SQL => "SELECT COUNT(*) FROM d724_escalation_outbox o LEFT JOIN d724_tenant t ON t.key_name = o.tenant_id AND t.status = 'active' WHERE o.status IN ('pending','retry','processing') AND t.key_name IS NULL" );
        ($Counts{InvalidAutomationDeliveries}) = $DBObject->FetchrowArray();
    }
    my $Success = !( grep { !$_ } values %Tables )
        && !$Counts{InvalidAutomationCommitments} && !$Counts{InvalidAutomationDeliveries};
    my $Status = { Success => $Success ? 1 : 0, Package => 'D724Commitment', Version => $VERSION, Tables => \%Tables, Counts => \%Counts };
    if ( $Self->GetOption('json') ) {
        $Self->Print( $Kernel::OM->Get('Kernel::System::JSON')->Encode( Data => $Status, SortKeys => 1, Pretty => 1 ) );
    }
    else {
        $Self->Print("CareOnCloud commitment status\nActive policies: $Counts{Policies}\nObjectives: $Counts{Objectives}\nActive commitments: $Counts{Active}\nBreached: $Counts{Breached}\nPending escalations: $Counts{PendingEscalations}\nDelivered escalations: $Counts{DeliveredEscalations}\nDead escalations: $Counts{DeadEscalations}\nReplayed escalations: $Counts{ReplayedEscalations}\n");
        $Self->Print( $Success ? "Status: OK\n" : "Status: FAILED\n" );
    }
    return $Success ? $Self->ExitCodeOk() : $Self->ExitCodeError();
}

1;
