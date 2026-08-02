# --
# Copyright (C) 2026 Data Market Bilgi Hizmetleri A.S.
# SPDX-License-Identifier: GPL-3.0-only
# --
package Kernel::System::Console::Command::Admin::D724::WebhookStatus;

use v5.24;
use strict;
use warnings;
use parent qw(Kernel::System::Console::BaseCommand);

our $VERSION = '0.3.0';
our @ObjectDependencies = ('Kernel::Config', 'Kernel::System::DB', 'Kernel::System::JSON');

sub Configure {
    my ($Self) = @_;
    $Self->Description('Validate lifecycle webhook subscription schema and cursor health.');
    $Self->AddOption( Name => 'json', Description => 'Print JSON.', Required => 0, HasValue => 0 );
    return;
}

sub Run {
    my ($Self) = @_;
    my $DB = $Kernel::OM->Get('Kernel::System::DB');
    my %Tables = map { $_ => 1 } $DB->ListTables();
    my $Table = $Tables{d724_webhook_subscription} ? 1 : 0;
    my %Counts = (
        Subscriptions => 0, Active => 0, Inactive => 0, TotalCursorLag => 0,
        MaximumCursorLag => 0, InvalidTenantReferences => 0,
        PendingDeliveries => 0, RetryDeliveries => 0, DeadDeliveries => 0,
        DeliveredLastHour => 0, OldestReadyAgeMinutes => 0,
    );
    my $QueryErrors = 0;
    if ($Table) {
        my @Queries = (
            [ Subscriptions => 'SELECT COUNT(*) FROM d724_webhook_subscription' ],
            [ Active => "SELECT COUNT(*) FROM d724_webhook_subscription WHERE status = 'active'" ],
            [ Inactive => "SELECT COUNT(*) FROM d724_webhook_subscription WHERE status = 'inactive'" ],
            [ InvalidTenantReferences => "SELECT COUNT(*) FROM d724_webhook_subscription s LEFT JOIN d724_tenant t ON t.key_name = s.tenant_id AND t.status = 'active' WHERE s.status = 'active' AND t.key_name IS NULL" ],
        );
        for my $Query (@Queries) {
            if ( !$DB->Prepare( SQL => $Query->[1] ) ) { $QueryErrors++; next }
            ( $Counts{ $Query->[0] } ) = $DB->FetchrowArray();
        }
        my $Active = 'active';
        if ( $DB->Prepare(
            SQL => 'SELECT COALESCE(SUM(GREATEST(COALESCE(h.last_sequence,0) - s.cursor_sequence,0)),0), COALESCE(MAX(GREATEST(COALESCE(h.last_sequence,0) - s.cursor_sequence,0)),0) FROM d724_webhook_subscription s LEFT JOIN d724_audit_head h ON h.tenant_id = s.tenant_id WHERE s.status = ?',
            Bind => [ \$Active ],
        ) ) {
            ( $Counts{TotalCursorLag}, $Counts{MaximumCursorLag} ) = $DB->FetchrowArray();
        }
        else { $QueryErrors++ }
        my @DeliveryQueries = (
            [ PendingDeliveries => "SELECT COUNT(*) FROM d724_escalation_outbox WHERE commitment_id = 0 AND action_key LIKE 'webhooksub%' AND status = 'pending'" ],
            [ RetryDeliveries => "SELECT COUNT(*) FROM d724_escalation_outbox WHERE commitment_id = 0 AND action_key LIKE 'webhooksub%' AND status = 'retry'" ],
            [ DeadDeliveries => "SELECT COUNT(*) FROM d724_escalation_outbox WHERE commitment_id = 0 AND action_key LIKE 'webhooksub%' AND status = 'dead'" ],
            [ DeliveredLastHour => "SELECT COUNT(*) FROM d724_escalation_outbox WHERE commitment_id = 0 AND action_key LIKE 'webhooksub%' AND status = 'delivered' AND processed_time >= DATE_SUB(current_timestamp, INTERVAL 1 HOUR)" ],
            [ OldestReadyAgeMinutes => "SELECT COALESCE(TIMESTAMPDIFF(MINUTE, MIN(available_time), current_timestamp),0) FROM d724_escalation_outbox WHERE commitment_id = 0 AND action_key LIKE 'webhooksub%' AND status IN ('pending','retry')" ],
        );
        for my $Query (@DeliveryQueries) {
            if ( !$DB->Prepare( SQL => $Query->[1] ) ) { $QueryErrors++; next }
            ( $Counts{ $Query->[0] } ) = $DB->FetchrowArray();
        }
    }
    my $Config = $Kernel::OM->Get('Kernel::Config');
    my $Enabled = $Config->Get('D724::Webhook::Enabled') ? 1 : 0;
    my $BacklogWarning = $Config->Get('D724::Webhook::BacklogWarningCount') // 100;
    my $AgeWarning = $Config->Get('D724::Webhook::OldestPendingWarningMinutes') // 10;
    my $AlertConfigValid = $BacklogWarning =~ m{\A[1-9][0-9]{0,5}\z}smx
        && $AgeWarning =~ m{\A[1-9][0-9]{0,4}\z}smx ? 1 : 0;
    my $BacklogAlert = $AlertConfigValid
        && $Counts{PendingDeliveries} + $Counts{RetryDeliveries} >= $BacklogWarning ? 1 : 0;
    my $AgeAlert = $AlertConfigValid && $Counts{OldestReadyAgeMinutes} >= $AgeWarning ? 1 : 0;
    my $DeadAlert = $Counts{DeadDeliveries} ? 1 : 0;
    my $Success = $Enabled && $Table && $AlertConfigValid && !$QueryErrors && !$Counts{InvalidTenantReferences};
    my $Status = {
        Success => $Success ? 1 : 0, Package => 'D724Webhook', Version => $VERSION, Enabled => $Enabled,
        Tables => { d724_webhook_subscription => $Table }, Counts => \%Counts, QueryErrors => $QueryErrors,
        Health => {
            Healthy => $Success && !$BacklogAlert && !$AgeAlert && !$DeadAlert ? 1 : 0,
            AlertConfigValid => $AlertConfigValid,
            BacklogWarningCount => 0 + $BacklogWarning,
            OldestPendingWarningMinutes => 0 + $AgeWarning,
            BacklogAlert => $BacklogAlert, AgeAlert => $AgeAlert, DeadLetterAlert => $DeadAlert,
        },
    };
    if ( $Self->GetOption('json') ) {
        $Self->Print( $Kernel::OM->Get('Kernel::System::JSON')->Encode( Data => $Status, SortKeys => 1, Pretty => 1 ) );
    }
    else {
        $Self->Print("CareOnCloud webhook status\nSubscriptions: $Counts{Subscriptions}\nActive: $Counts{Active}\nMaximum cursor lag: $Counts{MaximumCursorLag}\nPending/retry/dead: $Counts{PendingDeliveries}/$Counts{RetryDeliveries}/$Counts{DeadDeliveries}\nHealthy: " . ( $Status->{Health}->{Healthy} ? 'YES' : 'NO' ) . "\nStatus: " . ( $Success ? 'OK' : 'FAILED' ) . "\n");
    }
    return $Success ? $Self->ExitCodeOk() : $Self->ExitCodeError();
}

1;
