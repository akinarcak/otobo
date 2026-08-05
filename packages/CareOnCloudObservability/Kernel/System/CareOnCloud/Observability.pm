# --
# Copyright (C) 2026 Data Market Bilgi Hizmetleri A.S.
# SPDX-License-Identifier: GPL-3.0-only
# --
package Kernel::System::CareOnCloud::Observability;

use v5.24;
use strict;
use warnings;

our @ObjectDependencies = ('Kernel::Config', 'Kernel::System::DB');

my @Metric = (
    [ 'careoncloud_up',                         'Whether the consolidated CareOnCloud health probe succeeded.', 'Up' ],
    [ 'careoncloud_tenants_active',             'Number of active tenants.', 'ActiveTenants' ],
    [ 'careoncloud_api_requests_5m',            'API requests observed in the last five minutes.', 'APIRequests5m' ],
    [ 'careoncloud_api_server_errors_5m',       'API server errors observed in the last five minutes.', 'APIServerErrors5m' ],
    [ 'careoncloud_api_max_latency_ms_5m',      'Maximum API latency in milliseconds in the last five minutes.', 'APIMaxLatencyMS5m' ],
    [ 'careoncloud_webhook_pending',            'Webhook deliveries ready or waiting for retry.', 'WebhookPending' ],
    [ 'careoncloud_webhook_dead',               'Webhook deliveries in the dead-letter state.', 'WebhookDead' ],
    [ 'careoncloud_commitments_active',         'Commitments currently being evaluated.', 'CommitmentsActive' ],
    [ 'careoncloud_commitments_breached',       'Commitments currently breached.', 'CommitmentsBreached' ],
    [ 'careoncloud_escalations_pending',        'Escalation deliveries not yet completed.', 'EscalationsPending' ],
    [ 'careoncloud_escalations_dead',           'Escalation deliveries in the dead-letter state.', 'EscalationsDead' ],
    [ 'careoncloud_search_active',              'Whether the Elasticsearch runtime is active.', 'SearchActive' ],
    [ 'careoncloud_search_tenant_policy',       'Whether tenant-safe search policy is enabled.', 'SearchTenantPolicy' ],
    [ 'careoncloud_tenant_cache_active',        'Whether tenant cache isolation is enabled.', 'TenantCacheActive' ],
    [ 'careoncloud_alert_api_latency',           'Whether API maximum latency exceeds its configured threshold.', 'AlertAPILatency' ],
    [ 'careoncloud_alert_api_error_rate',        'Whether API server error rate exceeds its configured threshold.', 'AlertAPIErrorRate' ],
    [ 'careoncloud_alert_webhook_backlog',       'Whether webhook ready backlog exceeds its configured threshold.', 'AlertWebhookBacklog' ],
    [ 'careoncloud_alert_webhook_age',           'Whether the oldest ready webhook exceeds its age threshold.', 'AlertWebhookAge' ],
    [ 'careoncloud_alert_webhook_dead_letter',   'Whether any webhook delivery is dead-lettered.', 'AlertWebhookDeadLetter' ],
    [ 'careoncloud_observability_query_errors', 'Number of failed health queries in this scrape.', 'QueryErrors' ],
);

sub new { my ( $Type, %Param ) = @_; return bless \%Param, $Type }

sub StatusData {
    my ($Self) = @_;
    my $Config = $Kernel::OM->Get('Kernel::Config');
    my $DB = $Kernel::OM->Get('Kernel::System::DB');
    my %Tables = map { $_ => 1 } $DB->ListTables();
    my @Required = qw(careoncloud_tenant careoncloud_api_metric careoncloud_webhook_subscription careoncloud_commitment_instance careoncloud_escalation_outbox);
    my @Missing = grep { !$Tables{$_} } @Required;
    my %Value = map { $_->[2] => 0 } @Metric;

    my @Query = (
        [ ActiveTenants => "SELECT COUNT(*) FROM careoncloud_tenant WHERE status = 'active'", [qw(careoncloud_tenant)] ],
        [ [qw(APIRequests5m APIServerErrors5m APIMaxLatencyMS5m)], "SELECT COALESCE(SUM(request_count),0), COALESCE(SUM(CASE WHEN status_code >= 500 THEN request_count ELSE 0 END),0), COALESCE(MAX(duration_max_ms),0) FROM careoncloud_api_metric WHERE window_start >= DATE_SUB(DATE_FORMAT(current_timestamp, '%Y-%m-%d %H:%i:00'), INTERVAL 5 MINUTE)", [qw(careoncloud_api_metric)] ],
        [ [qw(WebhookPending WebhookDead WebhookOldestAgeMinutes)], "SELECT COALESCE(SUM(status IN ('pending','retry')),0), COALESCE(SUM(status = 'dead'),0), COALESCE(TIMESTAMPDIFF(MINUTE, MIN(CASE WHEN status IN ('pending','retry') THEN available_time END), current_timestamp),0) FROM careoncloud_escalation_outbox WHERE commitment_id = 0 AND action_key LIKE 'webhooksub%'", [qw(careoncloud_escalation_outbox)] ],
        [ [qw(CommitmentsActive CommitmentsBreached)], "SELECT COALESCE(SUM(status IN ('running','warning','paused')),0), COALESCE(SUM(status = 'breached'),0) FROM careoncloud_commitment_instance", [qw(careoncloud_commitment_instance)] ],
        [ [qw(EscalationsPending EscalationsDead)], "SELECT COALESCE(SUM(status IN ('pending','retry','processing')),0), COALESCE(SUM(status = 'dead'),0) FROM careoncloud_escalation_outbox", [qw(careoncloud_escalation_outbox)] ],
    );
    for my $Query (@Query) {
        next if grep { !$Tables{$_} } @{ $Query->[2] };
        if ( !$DB->Prepare( SQL => $Query->[1] ) ) { $Value{QueryErrors}++; next }
        my @Row = $DB->FetchrowArray();
        if ( !@Row ) { $Value{QueryErrors}++; next }
        my @Keys = ref $Query->[0] eq 'ARRAY' ? @{ $Query->[0] } : ( $Query->[0] );
        for my $Index ( 0 .. $#Keys ) { $Value{ $Keys[$Index] } = 0 + ( $Row[$Index] // 0 ) }
    }
    $Value{SearchActive}       = $Config->Get('Elasticsearch::Active') ? 1 : 0;
    $Value{SearchTenantPolicy} = $Config->Get('CareOnCloud::SearchPolicy::Enabled') ? 1 : 0;
    $Value{TenantCacheActive}  = $Config->Get('CareOnCloud::TenantCache::Enabled') ? 1 : 0;
    my $LatencyWarning = $Config->Get('CareOnCloud::API::LatencyWarningMs') // 2000;
    my $ErrorWarning = $Config->Get('CareOnCloud::API::ErrorRateWarningPercent') // 5;
    my $MinimumRequests = $Config->Get('CareOnCloud::API::MinimumAlertRequests') // 20;
    my $WebhookBacklogWarning = $Config->Get('CareOnCloud::Webhook::BacklogWarningCount') // 100;
    my $WebhookAgeWarning = $Config->Get('CareOnCloud::Webhook::OldestPendingWarningMinutes') // 10;
    my $ThresholdsValid = $LatencyWarning =~ m{\A[1-9][0-9]{0,5}\z}smx
        && $ErrorWarning =~ m{\A(?:[1-9]|[1-9][0-9]|100)\z}smx
        && $MinimumRequests =~ m{\A[1-9][0-9]{0,5}\z}smx
        && $WebhookBacklogWarning =~ m{\A[1-9][0-9]{0,5}\z}smx
        && $WebhookAgeWarning =~ m{\A[1-9][0-9]{0,4}\z}smx ? 1 : 0;
    $Value{AlertAPILatency} = $ThresholdsValid && $Value{APIMaxLatencyMS5m} >= $LatencyWarning ? 1 : 0;
    $Value{AlertAPIErrorRate} = $ThresholdsValid && $Value{APIRequests5m} >= $MinimumRequests
        && 100 * $Value{APIServerErrors5m} / $Value{APIRequests5m} >= $ErrorWarning ? 1 : 0;
    $Value{AlertWebhookBacklog} = $ThresholdsValid && $Value{WebhookPending} >= $WebhookBacklogWarning ? 1 : 0;
    $Value{AlertWebhookAge} = $ThresholdsValid && $Value{WebhookOldestAgeMinutes} >= $WebhookAgeWarning ? 1 : 0;
    $Value{AlertWebhookDeadLetter} = $Value{WebhookDead} ? 1 : 0;
    my $Enabled = $Config->Get('CareOnCloud::Observability::Enabled') ? 1 : 0;
    my $TokenDigest = lc( $Config->Get('CareOnCloud::Observability::MetricsTokenSHA256') // q{} );
    my $TokenConfigured = $TokenDigest =~ m{\A[0-9a-f]{64}\z}smx ? 1 : 0;
    my $Healthy = $Enabled && !@Missing && !$Value{QueryErrors} && $ThresholdsValid
        && $Value{SearchActive} && $Value{SearchTenantPolicy} && $Value{TenantCacheActive};
    $Value{Up} = $Healthy ? 1 : 0;
    return {
        Success => $Healthy ? 1 : 0, Package => 'CareOnCloudObservability', Version => '0.1.0',
        Enabled => $Enabled, TokenConfigured => $TokenConfigured,
        MissingTables => \@Missing, Values => \%Value, SeriesCount => scalar @Metric,
        ThresholdsValid => $ThresholdsValid,
    };
}

sub PrometheusRender {
    my ( $Self, %Param ) = @_;
    my $Status = $Param{Status} // $Self->StatusData();
    my $Output = "# CareOnCloud ESM bounded-cardinality metrics\n";
    for my $Metric (@Metric) {
        $Output .= "# HELP $Metric->[0] $Metric->[1]\n# TYPE $Metric->[0] gauge\n";
        $Output .= "$Metric->[0] " . ( 0 + ( $Status->{Values}->{ $Metric->[2] } // 0 ) ) . "\n";
    }
    return $Output;
}

sub MetricNames { return map { $_->[0] } @Metric }

1;
