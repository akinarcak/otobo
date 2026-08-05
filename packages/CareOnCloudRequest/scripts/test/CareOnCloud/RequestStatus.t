# --
# CareOnCloud ESM enterprise service management platform.
# Copyright (C) 2026 Data Market Bilgi Hizmetleri A.S.
# SPDX-License-Identifier: GPL-3.0-only
# --

use v5.24;
use strict;
use warnings;
use Capture::Tiny qw(capture);
use Test2::V0;
use Kernel::System::UnitTest::RegisterOM;

my $Command = $Kernel::OM->Get('Kernel::System::Console::Command::Admin::CareOnCloud::RequestStatus');
my ( $JSON, undef, $ExitCode ) = capture { return $Command->Execute('--json') };
is( $ExitCode, 0, 'request status succeeds' );
my $Status = $Kernel::OM->Get('Kernel::System::JSON')->Decode( Data => $JSON );
ok( $Status->{Success}, 'request schema is healthy' );
is( $Status->{Package}, 'CareOnCloudRequest', 'status identifies package' );
is( $Status->{Version}, '0.4.9', 'status identifies version' );
is( [ sort keys %{ $Status->{Tables} } ], [qw(careoncloud_request careoncloud_request_approval careoncloud_request_task)], 'all request tables reported' );

done_testing;
