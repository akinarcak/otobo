# --
# Copyright (C) 2026 Data Market Bilgi Hizmetleri A.S.
# SPDX-License-Identifier: GPL-3.0-only
# --
use v5.24;
use strict;
use warnings;
use Test2::V0;
use Kernel::System::UnitTest::RegisterOM;

$Kernel::OM->ObjectParamAdd( 'Kernel::System::UnitTest::Helper' => { RestoreDatabase => 1 } );
my $Helper = $Kernel::OM->Get('Kernel::System::UnitTest::Helper');
$Helper->ConfigSettingChange( Key => 'CareOnCloud::TenantGuard::Enabled', Value => 1 );
my $DB = $Kernel::OM->Get('Kernel::System::DB');
my $Guard = $Kernel::OM->Get('Kernel::System::CareOnCloud::TenantGuard');
my $Suffix = lc $Helper->GetRandomID();
my $Active = "daemon-active-$Suffix";
my $Inactive = "daemon-inactive-$Suffix";

for my $Fixture ( [ $Active, 'active' ], [ $Inactive, 'inactive' ] ) {
    my @Value = ( $Fixture->[0], 'Daemon ' . $Fixture->[1], $Fixture->[1], 1, 1, 1 );
    my @Bind = map { \$_ } @Value;
    ok(
        $DB->Do(
            SQL => 'INSERT INTO careoncloud_tenant (key_name, name, status, version, create_time, create_by, change_time, change_by) VALUES (?, ?, ?, ?, current_timestamp, ?, current_timestamp, ?)',
            Bind => \@Bind,
        ),
        "$Fixture->[1] tenant fixture is created",
    );
}

my $Allowed = $Guard->AutomationAuthorize( TenantID => $Active, JobName => 'commitment-sweep' );
ok( $Allowed->{Success}, 'active tenant receives daemon execution context' );
is( $Allowed->{Subject}->{ID}, 'automation:commitment-sweep', 'daemon subject identity is stable' );
is( $Allowed->{Subject}->{TenantIDs}, [$Active], 'daemon subject has exactly one tenant' );
is( $Allowed->{Subject}->{RoleBindings}, { $Active => ['automation'] }, 'automation role is tenant-bound' );

my $Denied = $Guard->AutomationAuthorize( TenantID => $Inactive, JobName => 'commitment-sweep' );
ok( !$Denied->{Success}, 'inactive tenant is denied before daemon work' );
is( $Denied->{Error}, 'TENANT_INACTIVE', 'inactive tenant denial is stable' );
is( $Guard->AutomationAuthorize( TenantID => 'bad tenant', JobName => 'job' )->{Error}, 'TENANT_ID_INVALID', 'ambiguous tenant is denied' );
is( $Guard->AutomationAuthorize( TenantID => $Active, JobName => '../job' )->{Error}, 'JOB_NAME_INVALID', 'unsafe job identity is denied' );

$Helper->ConfigSettingChange( Key => 'CareOnCloud::TenantGuard::Enabled', Value => 0 );
is(
    $Guard->AutomationAuthorize( TenantID => $Active, JobName => 'commitment-sweep' )->{Error},
    'AUTOMATION_FORBIDDEN',
    'disabled central policy prevents daemon execution',
);

done_testing;
