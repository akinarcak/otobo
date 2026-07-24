# --
# Copyright (C) 2026 Data Market Bilgi Hizmetleri A.S.
# SPDX-License-Identifier: GPL-3.0-only
# --
use v5.24;
use strict;
use warnings;
use Test2::V0;
use Kernel::System::UnitTest::RegisterOM;

my $Command = $Kernel::OM->Get('Kernel::System::Console::Command::Admin::D724::TicketAuditStatus');
my $DB = $Kernel::OM->Get('Kernel::System::DB');
ok( $DB->TableExists( Table => 'd724_ticket_scope' ), 'ticket scope table exists' );
is( $Command->Run(), 0, 'ticket audit status command succeeds' );
is( $Command->VERSION(), '0.1.0', 'ticket audit status command exposes package version' );
done_testing;
