# --
# CareOnCloud ESM enterprise service management platform.
# Copyright (C) 2026 Data Market Bilgi Hizmetleri A.S.
# SPDX-License-Identifier: GPL-3.0-only
# --

use v5.24;
use strict;
use warnings;
use utf8;
use Capture::Tiny qw(capture);
use Test2::V0;
use Kernel::System::UnitTest::RegisterOM;

my $Command = $Kernel::OM->Get('Kernel::System::Console::Command::Admin::D724::TenantDirectoryStatus');
my ( $JSON, undef, $ExitCode ) = capture { return $Command->Execute('--json') };
is( $ExitCode, 0, 'tenant directory status succeeds' );
my $Status = $Kernel::OM->Get('Kernel::System::JSON')->Decode( Data => $JSON );
ok( $Status->{Success}, 'tenant directory schema is healthy' );
is( $Status->{Package}, 'D724TenantDirectory', 'status identifies package' );
is( $Status->{Version}, '0.2.1', 'status identifies version' );
is( [ sort keys %{ $Status->{Tables} } ], [qw(d724_tenant d724_tenant_agent_role)], 'both directory tables reported' );

done_testing;
