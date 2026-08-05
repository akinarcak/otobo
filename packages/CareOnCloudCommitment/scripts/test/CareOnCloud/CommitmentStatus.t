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

my $Command = $Kernel::OM->Get('Kernel::System::Console::Command::Admin::CareOnCloud::CommitmentStatus');
my ( $JSON, undef, $ExitCode ) = capture { return $Command->Execute('--json') };
is( $ExitCode, 0, 'commitment status succeeds' );
my $Status = $Kernel::OM->Get('Kernel::System::JSON')->Decode( Data => $JSON );
ok( $Status->{Success}, 'commitment schema is healthy' );
is( $Status->{Package}, 'CareOnCloudCommitment', 'status identifies package' );
is( $Status->{Version}, '0.5.0', 'status identifies version' );
is(
    [ sort keys %{ $Status->{Tables} } ],
    [qw(careoncloud_commitment_event careoncloud_commitment_instance careoncloud_commitment_objective careoncloud_commitment_policy careoncloud_escalation_outbox)],
    'all commitment and escalation tables reported',
);
for my $Metric (qw(DeliveredEscalations DeliveredWebhooks DeadEscalations DeadWebhooks LifetimeAttempts ReplayedEscalations RetryEscalations)) {
    ok( exists $Status->{Counts}->{$Metric}, "status reports $Metric" );
}
is( $Status->{Counts}->{InvalidAutomationCommitments}, 0, 'no runnable commitment references inactive tenant' );
is( $Status->{Counts}->{InvalidAutomationDeliveries}, 0, 'no dispatchable outbox row references inactive tenant' );

done_testing;
