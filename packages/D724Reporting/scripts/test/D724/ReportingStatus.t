# --
# Copyright (C) 2026 Data Market Bilgi Hizmetleri A.S.
# SPDX-License-Identifier: GPL-3.0-only
# --
use v5.24;
use strict;
use warnings;
use Test2::V0;
use Kernel::System::UnitTest::RegisterOM;

my $Status = $Kernel::OM->Get('Kernel::System::Console::Command::Admin::D724::ReportingStatus')->StatusData();
ok( $Status->{Success}, 'reporting status is healthy' );
is( $Status->{Package}, 'D724Reporting', 'status identifies package' );
is( $Status->{Version}, '0.2.0', 'status identifies version' );
ok( $Status->{Enabled}, 'reporting is enabled' );
ok( $Status->{ConfigValid}, 'range configuration is valid' );
is( $Status->{CacheTTLSeconds}, 60, 'tenant summary cache TTL is explicit' );
is( [ sort keys %{ $Status->{Tables} } ], [qw(d724_catalog_item d724_commitment_instance d724_request d724_tenant d724_tenant_agent_role)], 'all reporting dependencies are present' );

done_testing;
