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
my $Catalog = $Kernel::OM->Get('Kernel::System::CareOnCloud::Catalog');
my $Tenant  = 'catalog-tx-' . lc $Helper->GetRandomID();
my $Zero    = '0' x 64;
my $Version = 1;
my $Handle  = $DB->Connect();

$Handle->commit() if !$Handle->{AutoCommit};
ok( $Handle->{AutoCommit}, 'catalog transaction test starts in production-style AutoCommit mode' );

my $Failed = $Catalog->_TransactionRun(
    Code => sub {
        my @Values = ( $Tenant, $Zero, $Version );
        my @Bind   = map { \$_ } @Values;
        die "fixture insert failed\n" if !$DB->Do(
            SQL => 'INSERT INTO careoncloud_audit_head (tenant_id, last_sequence, last_hash, version, change_time) VALUES (?, 0, ?, ?, current_timestamp)',
            Bind => \@Bind,
        );
        return { Success => 0, Error => 'INJECTED_AUDIT_FAILURE' };
    },
);
is( $Failed->{Error}, 'INJECTED_AUDIT_FAILURE', 'catalog domain failure is returned after rollback' );
$DB->Prepare( SQL => 'SELECT COUNT(*) FROM careoncloud_audit_head WHERE tenant_id = ?', Bind => [ \$Tenant ] );
my ($Count) = $DB->FetchrowArray();
is( $Count, 0, 'failed catalog operation leaves no committed mutation' );

my $Committed = $Catalog->_TransactionRun(
    Code => sub {
        my @Values = ( $Tenant, $Zero, $Version );
        my @Bind   = map { \$_ } @Values;
        die "fixture insert failed\n" if !$DB->Do(
            SQL => 'INSERT INTO careoncloud_audit_head (tenant_id, last_sequence, last_hash, version, change_time) VALUES (?, 0, ?, ?, current_timestamp)',
            Bind => \@Bind,
        );
        return { Success => 1 };
    },
);
ok( $Committed->{Success}, 'successful catalog operation commits' );
$DB->Prepare( SQL => 'SELECT COUNT(*) FROM careoncloud_audit_head WHERE tenant_id = ?', Bind => [ \$Tenant ] );
($Count) = $DB->FetchrowArray();
is( $Count, 1, 'successful catalog mutation is durable' );
ok( $DB->Do( SQL => 'DELETE FROM careoncloud_audit_head WHERE tenant_id = ?', Bind => [ \$Tenant ] ), 'fixture is removed' );

done_testing;
