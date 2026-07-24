# --
# D724 ESM is an enterprise service management platform based on OTOBO.
# Copyright (C) 2026 Data Market Bilgi Hizmetleri A.S.
# SPDX-License-Identifier: GPL-3.0-only
# --

use v5.24;
use strict;
use warnings;
use Capture::Tiny qw(capture);
use Test2::V0;
use Kernel::System::UnitTest::RegisterOM;

my $Command = $Kernel::OM->Get('Kernel::System::Console::Command::Admin::D724::CommitmentStatus');
my ( $JSON, undef, $ExitCode ) = capture { return $Command->Execute('--json') };
is( $ExitCode, 0, 'commitment status succeeds' );
my $Status = $Kernel::OM->Get('Kernel::System::JSON')->Decode( Data => $JSON );
ok( $Status->{Success}, 'commitment schema is healthy' );
is( $Status->{Package}, 'D724Commitment', 'status identifies package' );
is( $Status->{Version}, '0.3.5', 'status identifies version' );
is(
    [ sort keys %{ $Status->{Tables} } ],
    [qw(d724_commitment_event d724_commitment_instance d724_commitment_objective d724_commitment_policy d724_escalation_outbox)],
    'all commitment and escalation tables reported',
);

done_testing;
