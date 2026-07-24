# --
# Copyright (C) 2026 Data Market Bilgi Hizmetleri A.S.
# SPDX-License-Identifier: GPL-3.0-only
# --
use v5.24;
use strict;
use warnings;
use Test2::V0;
use Kernel::System::UnitTest::RegisterOM;

$Kernel::OM->ObjectParamAdd(
    'Kernel::System::UnitTest::Helper' => { RestoreDatabase => 0 },
);
my $Helper  = $Kernel::OM->Get('Kernel::System::UnitTest::Helper');
my $DB      = $Kernel::OM->Get('Kernel::System::DB');
my $Request = $Kernel::OM->Get('Kernel::System::D724::Request');
my $Tenant  = 'request-tx-' . lc $Helper->GetRandomID();
my $Zero    = '0' x 64;
my $Version = 1;

# The unit-test runner opens a process-wide rollback transaction even when
# RestoreDatabase is disabled. This contract test deliberately closes that
# empty wrapper before exercising the same AutoCommit path used by web calls.
my $Handle = $DB->Connect();
$Handle->commit() if !$Handle->{AutoCommit};
ok( $Handle->{AutoCommit}, 'transaction contract test starts in production-style AutoCommit mode' );

my $Failed = $Request->_TransactionRun(
    Code => sub {
        my @Values = ( $Tenant, $Zero, $Version );
        my @Bind   = map { \$_ } @Values;
        die "fixture insert failed\n" if !$DB->Do(
            SQL => 'INSERT INTO d724_audit_head (tenant_id, last_sequence, last_hash, version, change_time) VALUES (?, 0, ?, ?, current_timestamp)',
            Bind => \@Bind,
        );
        return { Success => 0, Error => 'INJECTED_AUDIT_FAILURE' };
    },
);
is( $Failed->{Error}, 'INJECTED_AUDIT_FAILURE', 'domain failure is returned after rollback' );
$DB->Prepare( SQL => 'SELECT COUNT(*) FROM d724_audit_head WHERE tenant_id = ?', Bind => [ \$Tenant ] );
my ($Count) = $DB->FetchrowArray();
is( $Count, 0, 'failed domain operation leaves no committed mutation' );

my $Committed = $Request->_TransactionRun(
    Code => sub {
        my @Values = ( $Tenant, $Zero, $Version );
        my @Bind   = map { \$_ } @Values;
        die "fixture insert failed\n" if !$DB->Do(
            SQL => 'INSERT INTO d724_audit_head (tenant_id, last_sequence, last_hash, version, change_time) VALUES (?, 0, ?, ?, current_timestamp)',
            Bind => \@Bind,
        );
        return { Success => 1 };
    },
);
ok( $Committed->{Success}, 'successful domain operation commits' );
$DB->Prepare( SQL => 'SELECT COUNT(*) FROM d724_audit_head WHERE tenant_id = ?', Bind => [ \$Tenant ] );
($Count) = $DB->FetchrowArray();
is( $Count, 1, 'successful mutation is durable after commit' );

my $DeletedTenant = $Tenant;
ok( $DB->Do( SQL => 'DELETE FROM d724_audit_head WHERE tenant_id = ?', Bind => [ \$DeletedTenant ] ), 'fixture is removed' );

done_testing;
