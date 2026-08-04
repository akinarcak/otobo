# --
# Copyright (C) 2026 Data Market Bilgi Hizmetleri A.S.
# SPDX-License-Identifier: GPL-3.0-only
# --
package Kernel::System::CareOnCloud::APIMetric;

use v5.24;
use strict;
use warnings;

our $VERSION = '0.7.2';
our @ObjectDependencies = ('Kernel::Config', 'Kernel::System::DB');

sub new { return bless {}, $_[0] }

sub Record {
    my ( $Self, %Param ) = @_;
    return { Success => 0, Error => 'METRICS_DISABLED' }
        if !$Kernel::OM->Get('Kernel::Config')->Get('CareOnCloud::API::MetricsEnabled');
    return { Success => 0, Error => 'TENANT_ID_INVALID' }
        if ( $Param{TenantID} // q{} ) ne '__public__'
        && ( $Param{TenantID} // q{} ) !~ m{\A[a-z0-9][a-z0-9_-]{1,127}\z}smx;
    return { Success => 0, Error => 'ROUTE_INVALID' }
        if ( $Param{Route} // q{} ) !~ m{\A[a-z][a-z0-9_]{0,49}\z}smx;
    return { Success => 0, Error => 'METHOD_INVALID' }
        if ( $Param{Method} // q{} ) !~ m{\A(?:GET|POST|PATCH|PUT|DELETE|OTHER)\z}smx;
    return { Success => 0, Error => 'STATUS_INVALID' }
        if ( $Param{StatusCode} // q{} ) !~ m{\A[1-5][0-9]{2}\z}smx;
    return { Success => 0, Error => 'ERROR_CODE_INVALID' }
        if length( $Param{ErrorCode} // q{} ) > 64
        || ( $Param{ErrorCode} // q{} ) !~ m{\A(?:[A-Z][A-Z0-9_]{1,63})?\z}smx;
    return { Success => 0, Error => 'DURATION_INVALID' }
        if ( $Param{DurationMS} // q{} ) !~ m{\A[0-9]+\z}smx || $Param{DurationMS} > 600_000;

    my $At = $Param{At} // $Kernel::OM->Create('Kernel::System::DateTime')->ToString();
    return { Success => 0, Error => 'TIME_INVALID' }
        if $At !~ m{\A([0-9]{4}-[0-9]{2}-[0-9]{2}[ ][0-9]{2}:[0-9]{2}):[0-9]{2}\z}smx;
    my $Window = "$1:00";
    my $Error = $Param{ErrorCode} // q{};
    my $Count = 1;
    my @Values = (
        $Param{TenantID}, $Window, $Param{Route}, $Param{Method}, $Param{StatusCode}, $Error,
        $Count, $Param{DurationMS}, $Param{DurationMS},
    );
    my @Bind = map { \$_ } @Values;
    return { Success => 0, Error => 'METRIC_WRITE_FAILED' }
        if !$Kernel::OM->Get('Kernel::System::DB')->Do(
            SQL => 'INSERT INTO careoncloud_api_metric (tenant_id, window_start, route_key, method_name, status_code, error_code, request_count, duration_sum_ms, duration_max_ms, create_time, change_time) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, current_timestamp, current_timestamp) ON DUPLICATE KEY UPDATE request_count = request_count + 1, duration_sum_ms = duration_sum_ms + VALUES(duration_sum_ms), duration_max_ms = GREATEST(duration_max_ms, VALUES(duration_max_ms)), change_time = current_timestamp',
            Bind => \@Bind,
        );
    return { Success => 1 };
}

1;
