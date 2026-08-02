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

my $Command = $Kernel::OM->Get('Kernel::System::Console::Command::Admin::D724::TicketAuditStatus');
my ( $JSON, undef, $ExitCode ) = capture { return $Command->Execute('--json') };
is( $ExitCode, 0, 'ticket audit status command succeeds' );
my $Status = $Kernel::OM->Get('Kernel::System::JSON')->Decode( Data => $JSON );
ok( $Status->{Success}, 'ticket audit schema is healthy' );
is( $Status->{Package}, 'D724TicketAudit', 'status identifies package' );
is( $Status->{Version}, '0.8.7', 'status identifies version' );
ok( $Status->{SearchPolicy}->{Enabled}, 'tenant search policy is enabled' );
ok( $Status->{SearchPolicy}->{ConfigValid}, 'only the supported ticket index is declared tenant-safe' );
is( $Status->{SearchPolicy}->{DirectUnscopedRequest}, 'deny', 'unscoped direct search behavior is explicit' );
ok( $Status->{Tables}->{d724_ticket_scope}, 'ticket scope table is reported' );
is( $Status->{Counts}->{UnboundTickets}, 0, 'no legacy ticket is left outside tenant scope' );
is( $Status->{Counts}->{InvalidTenantTickets}, 0, 'every core ticket maps to an active D724 tenant' );
is( $Status->{Unbound}, [], 'unbound ticket detail list is empty at healthy gate' );
done_testing;
