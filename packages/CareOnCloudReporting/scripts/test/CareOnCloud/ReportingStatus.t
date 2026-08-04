# --
# Copyright (C) 2026 Data Market Bilgi Hizmetleri A.S.
# SPDX-License-Identifier: GPL-3.0-only
# --
use v5.24;
use strict;
use warnings;
use Test2::V0;
use Kernel::System::UnitTest::RegisterOM;

my $Status = $Kernel::OM->Get('Kernel::System::Console::Command::Admin::CareOnCloud::ReportingStatus')->StatusData();
ok( $Status->{Success}, 'reporting status is healthy' );
is( $Status->{Package}, 'CareOnCloudReporting', 'status identifies package' );
is( $Status->{Version}, '0.4.1', 'status identifies version' );
ok( $Status->{Enabled}, 'reporting is enabled' );
ok( $Status->{ConfigValid}, 'range configuration is valid' );
is( $Status->{CacheTTLSeconds}, 60, 'tenant summary cache TTL is explicit' );
is( [ sort keys %{ $Status->{Tables} } ], [qw(careoncloud_catalog_item careoncloud_commitment_instance careoncloud_request careoncloud_tenant careoncloud_tenant_agent_role)], 'all reporting dependencies are present' );

done_testing;
