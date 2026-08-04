# --
# Copyright (C) 2026 Data Market Bilgi Hizmetleri A.S.
# SPDX-License-Identifier: GPL-3.0-only
# --
package Kernel::System::Console::Command::Maint::CareOnCloud::APIRetentionCleanup;

use v5.24;
use strict;
use warnings;
use parent qw(Kernel::System::Console::BaseCommand);

our $VERSION = '0.7.2';
our @ObjectDependencies = ( 'Kernel::Config', 'Kernel::System::DB' );

sub Configure {
    my ($Self) = @_;
    $Self->Description('Delete API token digests and rate windows older than configured retention.');
    $Self->AddOption(
        Name => 'confirm', Description => 'Confirm retention deletion.',
        Required => 1, HasValue => 0,
    );
    return;
}

sub Run {
    my ($Self) = @_;
    return $Self->ExitCodeError() if !$Self->GetOption('confirm');
    my $Config = $Kernel::OM->Get('Kernel::Config');
    my $TokenDays = $Config->Get('CareOnCloud::API::TokenRetentionDays') // 30;
    my $RateHours = $Config->Get('CareOnCloud::API::RateRetentionHours') // 48;
    my $MetricHours = $Config->Get('CareOnCloud::API::MetricRetentionHours') // 168;
    if ( $TokenDays !~ m{\A[1-9][0-9]{0,3}\z}smx || $RateHours !~ m{\A[1-9][0-9]{0,4}\z}smx
        || $MetricHours !~ m{\A[1-9][0-9]{0,3}\z}smx ) {
        $Self->PrintError('Invalid API retention configuration.');
        return $Self->ExitCodeError();
    }

    my $DB = $Kernel::OM->Get('Kernel::System::DB');
    my $Handle = $DB->Connect();
    if (!$Handle) {
        $Self->PrintError('Database unavailable.');
        return $Self->ExitCodeError();
    }
    my $OwnTransaction = $Handle->{AutoCommit} ? 1 : 0;
    my ( $TokenCount, $RateCount, $MetricCount );
    my $OK = eval {
        $DB->BeginWork() if $OwnTransaction;
        $DB->Prepare(
            SQL => "SELECT COUNT(*) FROM careoncloud_api_token WHERE (status = 'revoked' OR expires_at <= current_timestamp) AND create_time < DATE_SUB(current_timestamp, INTERVAL ? DAY)",
            Bind => [ \$TokenDays ],
        ) or die "TOKEN_COUNT_FAILED\n";
        ($TokenCount) = $DB->FetchrowArray();
        $DB->Prepare(
            SQL => 'SELECT COUNT(*) FROM careoncloud_api_rate WHERE window_start < DATE_SUB(current_timestamp, INTERVAL ? HOUR)',
            Bind => [ \$RateHours ],
        ) or die "RATE_COUNT_FAILED\n";
        ($RateCount) = $DB->FetchrowArray();
        $DB->Prepare(
            SQL => 'SELECT COUNT(*) FROM careoncloud_api_metric WHERE window_start < DATE_SUB(current_timestamp, INTERVAL ? HOUR)',
            Bind => [ \$MetricHours ],
        ) or die "METRIC_COUNT_FAILED\n";
        ($MetricCount) = $DB->FetchrowArray();
        $DB->Do(
            SQL => "DELETE FROM careoncloud_api_token WHERE (status = 'revoked' OR expires_at <= current_timestamp) AND create_time < DATE_SUB(current_timestamp, INTERVAL ? DAY)",
            Bind => [ \$TokenDays ],
        ) or die "TOKEN_DELETE_FAILED\n";
        $DB->Do(
            SQL => 'DELETE FROM careoncloud_api_rate WHERE window_start < DATE_SUB(current_timestamp, INTERVAL ? HOUR)',
            Bind => [ \$RateHours ],
        ) or die "RATE_DELETE_FAILED\n";
        $DB->Do(
            SQL => 'DELETE FROM careoncloud_api_metric WHERE window_start < DATE_SUB(current_timestamp, INTERVAL ? HOUR)',
            Bind => [ \$MetricHours ],
        ) or die "METRIC_DELETE_FAILED\n";
        $Handle->commit() if $OwnTransaction;
        1;
    };
    if (!$OK) {
        eval { $DB->Rollback() } if $OwnTransaction;
        $Self->PrintError('API retention cleanup failed.');
        return $Self->ExitCodeError();
    }
    $Self->Print("DeletedTokenDigests=$TokenCount\nDeletedRateWindows=$RateCount\nDeletedMetricWindows=$MetricCount\n");
    return $Self->ExitCodeOk();
}

1;
