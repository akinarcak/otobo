# --
# D724 ESM is an enterprise service management platform based on OTOBO.
# Copyright (C) 2026 Data Market Bilgi Hizmetleri A.S.
# SPDX-License-Identifier: GPL-3.0-only
# --

package Kernel::System::Console::Command::Admin::D724::CommitmentStatus;

use v5.24;
use strict;
use warnings;
use parent qw(Kernel::System::Console::BaseCommand);

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
    my %Counts = ( Policies => 0, Objectives => 0, Active => 0, Breached => 0, PendingEscalations => 0, DeadEscalations => 0 );
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
    }
    if ( $Tables{d724_escalation_outbox} ) {
        $DBObject->Prepare( SQL => "SELECT COUNT(*) FROM d724_escalation_outbox WHERE status IN ('pending','retry','processing')" );
        ($Counts{PendingEscalations}) = $DBObject->FetchrowArray();
        $DBObject->Prepare( SQL => "SELECT COUNT(*) FROM d724_escalation_outbox WHERE status = 'dead'" );
        ($Counts{DeadEscalations}) = $DBObject->FetchrowArray();
    }
    my $Success = !( grep { !$_ } values %Tables );
    my $Status = { Success => $Success ? 1 : 0, Package => 'D724Commitment', Version => '0.3.2', Tables => \%Tables, Counts => \%Counts };
    if ( $Self->GetOption('json') ) {
        $Self->Print( $Kernel::OM->Get('Kernel::System::JSON')->Encode( Data => $Status, SortKeys => 1, Pretty => 1 ) );
    }
    else {
        $Self->Print("D724 commitment status\nActive policies: $Counts{Policies}\nObjectives: $Counts{Objectives}\nActive commitments: $Counts{Active}\nBreached: $Counts{Breached}\nPending escalations: $Counts{PendingEscalations}\nDead escalations: $Counts{DeadEscalations}\n");
        $Self->Print( $Success ? "Status: OK\n" : "Status: FAILED\n" );
    }
    return $Success ? $Self->ExitCodeOk() : $Self->ExitCodeError();
}

1;
