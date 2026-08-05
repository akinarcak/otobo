# --
# Copyright (C) 2026 Data Market Bilgi Hizmetleri A.S.
# SPDX-License-Identifier: GPL-3.0-only
# --
use v5.24;
use strict;
use warnings;
use Test2::V0;
use Kernel::System::UnitTest::RegisterOM;

$Kernel::OM->ObjectParamAdd('Kernel::System::UnitTest::Helper' => { RestoreDatabase => 1 });
my $Helper = $Kernel::OM->Get('Kernel::System::UnitTest::Helper');
$Helper->ConfigSettingChange( Key => 'CareOnCloud::API::MetricsEnabled', Value => 1 );
my $Metric = $Kernel::OM->Get('Kernel::System::CareOnCloud::APIMetric');
my $DB = $Kernel::OM->Get('Kernel::System::DB');
my $Tenant = 'metric-' . lc $Helper->GetRandomID();

my $First = $Metric->Record(
    TenantID => $Tenant, Route => 'tickets', Method => 'GET', StatusCode => 200,
    ErrorCode => q{}, DurationMS => 12, At => '2030-01-02 03:04:05',
);
ok( $First->{Success}, 'first bounded route observation is recorded' ) or diag( $First->{Error} // 'unknown' );
ok( $Metric->Record(
    TenantID => $Tenant, Route => 'tickets', Method => 'GET', StatusCode => 200,
    ErrorCode => q{}, DurationMS => 28, At => '2030-01-02 03:04:55',
)->{Success}, 'same minute and dimensions aggregate atomically' );
ok( $Metric->Record(
    TenantID => $Tenant, Route => 'tickets', Method => 'GET', StatusCode => 503,
    ErrorCode => 'DATABASE_ERROR', DurationMS => 31, At => '2030-01-02 03:04:56',
)->{Success}, 'status and error dimension creates a separate bounded series' );
ok( $Metric->Record(
    TenantID => '__public__', Route => 'token', Method => 'POST', StatusCode => 401,
    ErrorCode => 'INVALID_CLIENT', DurationMS => 7, At => '2030-01-02 03:04:57',
)->{Success}, 'unauthenticated transport metrics use the reserved public boundary' );

my $Route = 'tickets';
$DB->Prepare(
    SQL => 'SELECT request_count, duration_sum_ms, duration_max_ms FROM careoncloud_api_metric WHERE tenant_id = ? AND route_key = ? AND status_code = 200',
    Bind => [ \$Tenant, \$Route ], Limit => 1,
);
my @Aggregate = $DB->FetchrowArray();
is( \@Aggregate, [ 2, 40, 28 ], 'aggregate retains count, sum and maximum latency' );
$DB->Prepare( SQL => 'SELECT COUNT(*) FROM careoncloud_api_metric WHERE tenant_id = ?', Bind => [ \$Tenant ] );
my ($Series) = $DB->FetchrowArray();
is( $Series, 2, 'status and error are bounded series dimensions' );
is( $Metric->Record(
    TenantID => $Tenant, Route => '/tickets/123', Method => 'GET', StatusCode => 200,
    ErrorCode => q{}, DurationMS => 1,
)->{Error}, 'ROUTE_INVALID', 'raw paths cannot create high-cardinality route labels' );
is( $Metric->Record(
    TenantID => '../tenant', Route => 'tickets', Method => 'GET', StatusCode => 200,
    ErrorCode => q{}, DurationMS => 1,
)->{Error}, 'TENANT_ID_INVALID', 'invalid tenant labels fail closed' );
is( $Metric->Record(
    TenantID => $Tenant, Route => 'tickets', Method => 'GET', StatusCode => 200,
    ErrorCode => q{}, DurationMS => 600_001,
)->{Error}, 'DURATION_INVALID', 'unbounded latency input is rejected' );

done_testing;
