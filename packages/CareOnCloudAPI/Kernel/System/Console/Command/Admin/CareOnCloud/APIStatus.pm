# --
# Copyright (C) 2026 Data Market Bilgi Hizmetleri A.S.
# SPDX-License-Identifier: GPL-3.0-only
# --
package Kernel::System::Console::Command::Admin::CareOnCloud::APIStatus;

use v5.24;
use strict;
use warnings;
use parent qw(Kernel::System::Console::BaseCommand);

our $VERSION = '0.7.2';
our @ObjectDependencies = (
    'Kernel::Config', 'Kernel::System::DB', 'Kernel::System::JSON', 'Kernel::System::Main',
);

sub Configure {
    my ($Self) = @_;
    $Self->Description('Validate CareOnCloud API authorization storage, transport and operational invariants.');
    $Self->AddOption(
        Name => 'json', Description => 'Print JSON.', Required => 0, HasValue => 0,
    );
    return;
}

sub StatusData {
    my ($Self) = @_;
    my $DB = $Kernel::OM->Get('Kernel::System::DB');
    my %Table = map { $_ => 1 } $DB->ListTables();
    my @Needed = qw(careoncloud_api_client careoncloud_api_token careoncloud_api_rate careoncloud_api_metric);
    my @Missing = grep { !$Table{$_} } @Needed;
    my %Count = map { $_ => 0 } qw(
        Clients ActiveClients RevokedClients Tokens ActiveTokens RevokedTokens
        ExpiredActiveTokens RateWindows CurrentWindowRequests StaleTokenDigests
        StaleRateWindows InvalidTenantClients InvalidSecretHashes InvalidTokenHashes
        DuplicateRateWindows RateWindowUnique QueryErrors
        MetricWindows Requests5m ClientErrors5m ServerErrors5m DurationSumMS5m
        MaximumLatencyMS5m RouteSeries5m StaleMetricWindows InvalidMetricTenantRefs
        MetricSeriesUnique AverageLatencyMS5m
    );

    my $Config = $Kernel::OM->Get('Kernel::Config');
    my $TokenDays = $Config->Get('CareOnCloud::API::TokenRetentionDays') // 30;
    my $RateHours = $Config->Get('CareOnCloud::API::RateRetentionHours') // 48;
    my $MetricHours = $Config->Get('CareOnCloud::API::MetricRetentionHours') // 168;
    my $LatencyWarningMS = $Config->Get('CareOnCloud::API::LatencyWarningMs') // 2000;
    my $ErrorWarningPercent = $Config->Get('CareOnCloud::API::ErrorRateWarningPercent') // 5;
    my $MinimumAlertRequests = $Config->Get('CareOnCloud::API::MinimumAlertRequests') // 20;
    my $RetentionValid = $TokenDays =~ m{\A[1-9][0-9]{0,3}\z}smx
        && $RateHours =~ m{\A[1-9][0-9]{0,4}\z}smx
        && $MetricHours =~ m{\A[1-9][0-9]{0,3}\z}smx ? 1 : 0;
    my $AlertConfigValid = $LatencyWarningMS =~ m{\A[1-9][0-9]{0,5}\z}smx
        && $ErrorWarningPercent =~ m{\A(?:[1-9]|[1-9][0-9]|100)\z}smx
        && $MinimumAlertRequests =~ m{\A[1-9][0-9]{0,5}\z}smx ? 1 : 0;

    if ( !@Missing ) {
        $Self->_Query(
            DB => $DB, Count => \%Count,
            SQL => "SELECT COUNT(*), SUM(status = 'active'), SUM(status = 'revoked') FROM careoncloud_api_client",
            Keys => [qw(Clients ActiveClients RevokedClients)],
        );
        $Self->_Query(
            DB => $DB, Count => \%Count,
            SQL => "SELECT COUNT(*), SUM(status = 'active' AND expires_at > current_timestamp), SUM(status = 'revoked'), SUM(status = 'active' AND expires_at <= current_timestamp) FROM careoncloud_api_token",
            Keys => [qw(Tokens ActiveTokens RevokedTokens ExpiredActiveTokens)],
        );
        $Self->_Query(
            DB => $DB, Count => \%Count,
            SQL => "SELECT COUNT(*), COALESCE(SUM(CASE WHEN window_start = DATE_FORMAT(current_timestamp, '%Y-%m-%d %H:%i:00') THEN request_count ELSE 0 END), 0) FROM careoncloud_api_rate",
            Keys => [qw(RateWindows CurrentWindowRequests)],
        );
        $Self->_Query(
            DB => $DB, Count => \%Count,
            SQL => "SELECT COUNT(*) FROM careoncloud_api_client c LEFT JOIN careoncloud_tenant t ON t.key_name = c.tenant_id AND t.status = 'active' WHERE t.key_name IS NULL",
            Keys => ['InvalidTenantClients'],
        );
        $Self->_Query(
            DB => $DB, Count => \%Count,
            SQL => "SELECT COUNT(*) FROM careoncloud_api_client WHERE secret_hash NOT LIKE 'BCRYPT:%'",
            Keys => ['InvalidSecretHashes'],
        );
        $Self->_Query(
            DB => $DB, Count => \%Count,
            SQL => q{SELECT COUNT(*) FROM careoncloud_api_token WHERE token_hash NOT REGEXP '^[0-9a-f]{64}$'},
            Keys => ['InvalidTokenHashes'],
        );
        $Self->_Query(
            DB => $DB, Count => \%Count,
            SQL => 'SELECT COUNT(*) FROM (SELECT client_id, window_start, COUNT(*) n FROM careoncloud_api_rate GROUP BY client_id, window_start HAVING n > 1) d',
            Keys => ['DuplicateRateWindows'],
        );
        my %Index;
        $Self->_Query(
            DB => $DB, Count => \%Index,
            SQL => "SELECT COUNT(*) FROM information_schema.statistics WHERE table_schema = DATABASE() AND table_name = 'careoncloud_api_rate' AND index_name = 'careoncloud_api_rate_window'",
            Keys => ['Columns'],
        );
        $Count{QueryErrors} += $Index{QueryErrors} // 0;
        $Count{RateWindowUnique} = ( $Index{Columns} // 0 ) == 2 ? 1 : 0;
        $Self->_Query(
            DB => $DB, Count => \%Count,
            SQL => 'SELECT COUNT(*) FROM careoncloud_api_metric', Keys => ['MetricWindows'],
        );
        $Self->_Query(
            DB => $DB, Count => \%Count,
            SQL => "SELECT COALESCE(SUM(request_count),0), COALESCE(SUM(CASE WHEN status_code BETWEEN 400 AND 499 THEN request_count ELSE 0 END),0), COALESCE(SUM(CASE WHEN status_code >= 500 THEN request_count ELSE 0 END),0), COALESCE(SUM(duration_sum_ms),0), COALESCE(MAX(duration_max_ms),0), COUNT(*) FROM careoncloud_api_metric WHERE window_start >= DATE_SUB(DATE_FORMAT(current_timestamp, '%Y-%m-%d %H:%i:00'), INTERVAL 5 MINUTE)",
            Keys => [qw(Requests5m ClientErrors5m ServerErrors5m DurationSumMS5m MaximumLatencyMS5m RouteSeries5m)],
        );
        $Self->_Query(
            DB => $DB, Count => \%Count,
            SQL => "SELECT COUNT(*) FROM careoncloud_api_metric m LEFT JOIN careoncloud_tenant t ON t.key_name = m.tenant_id WHERE m.tenant_id <> '__public__' AND t.key_name IS NULL",
            Keys => ['InvalidMetricTenantRefs'],
        );
        my %MetricIndex;
        $Self->_Query(
            DB => $DB, Count => \%MetricIndex,
            SQL => "SELECT COUNT(*) FROM information_schema.statistics WHERE table_schema = DATABASE() AND table_name = 'careoncloud_api_metric' AND index_name = 'careoncloud_api_metric_series'",
            Keys => ['Columns'],
        );
        $Count{QueryErrors} += $MetricIndex{QueryErrors} // 0;
        $Count{MetricSeriesUnique} = ( $MetricIndex{Columns} // 0 ) == 6 ? 1 : 0;

        if ($RetentionValid) {
            $Self->_Query(
                DB => $DB, Count => \%Count,
                SQL => "SELECT COUNT(*) FROM careoncloud_api_token WHERE (status = 'revoked' OR expires_at <= current_timestamp) AND create_time < DATE_SUB(current_timestamp, INTERVAL ? DAY)",
                Bind => [ \$TokenDays ], Keys => ['StaleTokenDigests'],
            );
            $Self->_Query(
                DB => $DB, Count => \%Count,
                SQL => 'SELECT COUNT(*) FROM careoncloud_api_rate WHERE window_start < DATE_SUB(current_timestamp, INTERVAL ? HOUR)',
                Bind => [ \$RateHours ], Keys => ['StaleRateWindows'],
            );
            $Self->_Query(
                DB => $DB, Count => \%Count,
                SQL => 'SELECT COUNT(*) FROM careoncloud_api_metric WHERE window_start < DATE_SUB(current_timestamp, INTERVAL ? HOUR)',
                Bind => [ \$MetricHours ], Keys => ['StaleMetricWindows'],
            );
        }
    }
    $_ //= 0 for values %Count;
    $Count{AverageLatencyMS5m} = $Count{Requests5m}
        ? int( $Count{DurationSumMS5m} / $Count{Requests5m} + 0.5 ) : 0;
    my $ServerErrorRatePercent = $Count{Requests5m}
        ? 100 * $Count{ServerErrors5m} / $Count{Requests5m} : 0;
    my $LatencyAlert = $AlertConfigValid && $Count{MaximumLatencyMS5m} >= $LatencyWarningMS ? 1 : 0;
    my $ErrorRateAlert = $AlertConfigValid && $Count{Requests5m} >= $MinimumAlertRequests
        && $ServerErrorRatePercent >= $ErrorWarningPercent ? 1 : 0;

    my $Home = $Config->Get('Home');
    my $Main = $Kernel::OM->Get('Kernel::System::Main');
    my $OpenAPI = $Main->FileRead(
        Location => "$Home/var/httpd/htdocs/careoncloud/api/openapi-v1.json",
        Mode => 'utf8', Result => 'SCALAR',
    );
    my $Contract = $OpenAPI
        ? eval { $Kernel::OM->Get('Kernel::System::JSON')->Decode( Data => ${$OpenAPI} ) }
        : undef;
    my $ContractOK = $OpenAPI && !$@ && ref $Contract eq 'HASH'
        && ( $Contract->{openapi} // q{} ) eq '3.1.0' ? 1 : 0;
    my $WebhookContractOK = $ContractOK
        && ref $Contract->{paths}->{'/webhook-subscriptions'} eq 'HASH'
        && ref $Contract->{paths}->{'/webhook-subscriptions/{subscription_id}'} eq 'HASH' ? 1 : 0;
    my $PSGI = $Main->FileRead(
        Location => "$Home/bin/psgi-bin/careoncloud.psgi", Mode => 'utf8', Result => 'SCALAR',
    );
    my $MountOK = $PSGI && ${$PSGI} =~ m{mount[ ]+'/api/v1'}smx ? 1 : 0;
    my $WebhookMountOK = $MountOK && ${$PSGI} =~ m{/webhook-subscriptions}smx ? 1 : 0;

    my $Success = !@Missing && $RetentionValid && $AlertConfigValid
        && $Count{RateWindowUnique} && $Count{MetricSeriesUnique}
        && !$Count{QueryErrors} && !$Count{InvalidTenantClients}
        && !$Count{InvalidMetricTenantRefs}
        && !$Count{InvalidSecretHashes} && !$Count{InvalidTokenHashes}
        && !$Count{DuplicateRateWindows} && $ContractOK && $MountOK && $WebhookContractOK && $WebhookMountOK;
    return {
        Success => $Success ? 1 : 0, Package => 'CareOnCloudAPI', Version => $VERSION,
        Enabled => $Config->Get('CareOnCloud::API::Enabled') ? 1 : 0,
        MissingTables => \@Missing, Counts => \%Count,
        Retention => {
            Valid => $RetentionValid, TokenDays => 0 + $TokenDays, RateHours => 0 + $RateHours,
            MetricHours => 0 + $MetricHours,
        },
        Health => {
            Healthy => $Success && !$LatencyAlert && !$ErrorRateAlert ? 1 : 0,
            AlertConfigValid => $AlertConfigValid,
            ServerErrorRatePercent5m => 0 + sprintf( '%.2f', $ServerErrorRatePercent ),
            LatencyWarningMS => 0 + $LatencyWarningMS,
            ErrorRateWarningPercent => 0 + $ErrorWarningPercent,
            MinimumAlertRequests => 0 + $MinimumAlertRequests,
            LatencyAlert => $LatencyAlert, ErrorRateAlert => $ErrorRateAlert,
        },
        Transport => {
            CanonicalMount => $MountOK, OpenAPI31 => $ContractOK,
            WebhookContract => $WebhookContractOK, WebhookMount => $WebhookMountOK,
        },
    };
}

sub _Query {
    my ( $Self, %Param ) = @_;
    my %Prepare = ( SQL => $Param{SQL} );
    $Prepare{Bind} = $Param{Bind} if $Param{Bind};
    if ( !$Param{DB}->Prepare(%Prepare) ) {
        $Param{Count}->{QueryErrors}++;
        return;
    }
    my @Row = $Param{DB}->FetchrowArray();
    if ( !@Row ) {
        $Param{Count}->{QueryErrors}++;
        return;
    }
    @{$Param{Count}}{ @{ $Param{Keys} } } = @Row;
    return 1;
}

sub Run {
    my ($Self) = @_;
    my $Status = $Self->StatusData();
    if ( $Self->GetOption('json') ) {
        $Self->Print(
            $Kernel::OM->Get('Kernel::System::JSON')->Encode(
                Data => $Status, SortKeys => 1, Pretty => 1,
            ) . "\n",
        );
    }
    else {
        $Self->Print("CareOnCloud API $VERSION: " . ( $Status->{Success} ? 'OK' : 'FAILED' ) . "\n");
    }
    return $Status->{Success} ? $Self->ExitCodeOk() : $Self->ExitCodeError();
}

1;
