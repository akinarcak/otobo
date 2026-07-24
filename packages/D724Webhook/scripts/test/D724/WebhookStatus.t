# --
# Copyright (C) 2026 Data Market Bilgi Hizmetleri A.S.
# SPDX-License-Identifier: GPL-3.0-only
# --
use v5.24;
use strict;
use warnings;
use Capture::Tiny qw(capture);
use Test2::V0;
use Kernel::System::UnitTest::RegisterOM;

my $Command = $Kernel::OM->Get('Kernel::System::Console::Command::Admin::D724::WebhookStatus');
my ( $JSON, undef, $ExitCode ) = capture { return $Command->Execute('--json') };
is( $ExitCode, 0, 'webhook status succeeds' );
my $Status = $Kernel::OM->Get('Kernel::System::JSON')->Decode( Data => $JSON );
ok( $Status->{Success}, 'webhook subscription schema is healthy' );
is( $Status->{Package}, 'D724Webhook', 'status identifies package' );
is( $Status->{Version}, '0.1.0', 'status identifies version' );
ok( $Status->{Tables}->{d724_webhook_subscription}, 'subscription table is present' );
is( $Status->{QueryErrors}, 0, 'status queries are error free' );
for my $Metric (qw(Subscriptions Active Inactive TotalCursorLag MaximumCursorLag InvalidTenantReferences)) {
    ok( exists $Status->{Counts}->{$Metric}, "status reports $Metric" );
}

done_testing;
