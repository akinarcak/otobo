# --
# Copyright (C) 2026 Data Market Bilgi Hizmetleri A.S.
# SPDX-License-Identifier: GPL-3.0-only
# --
use v5.24;
use strict;
use warnings;
use Test2::V0;
use Kernel::System::UnitTest::RegisterOM;

$Kernel::OM->ObjectParamAdd( 'Kernel::System::UnitTest::Helper' => { RestoreDatabase => 0 } );
my $Helper    = $Kernel::OM->Get('Kernel::System::UnitTest::Helper');
my $DB        = $Kernel::OM->Get('Kernel::System::DB');
my $Directory = $Kernel::OM->Get('Kernel::System::D724::TenantDirectory');
my $Audit     = $Kernel::OM->Get('Kernel::System::D724::Audit');
my $Tenant    = 'directory-audit-rollback-' . lc $Helper->GetRandomID();
my $Role      = 'auditor';
my $Platform  = { ID => 'platform-rollback-test', Roles => ['platform_admin'], TenantIDs => ['bootstrap'] };
my $Subject   = { ID => 'tenant-rollback-test', TenantIDs => [$Tenant], RoleBindings => { $Tenant => ['tenant_admin'] } };
my $Handle    = $DB->Connect();

$Helper->ConfigSettingChange( Key => 'D724::TenantGuard::Enabled', Value => 1 );
$Helper->ConfigSettingChange( Key => 'D724::TenantGuard::AllowPlatformAdmin', Value => 1 );
$Helper->ConfigSettingChange( Key => 'D724::Audit::Enabled', Value => 1 );
$Handle->commit() if !$Handle->{AutoCommit};
ok( $Handle->{AutoCommit}, 'audit rollback test starts in production-style AutoCommit mode' );
ok(
    $Directory->TenantCreate( Subject => $Platform, TenantID => $Tenant, Name => 'Directory Audit Rollback', UserID => 1 )->{Success},
    'rollback fixture tenant is created',
);

$Helper->ConfigSettingChange( Key => 'D724::Audit::Enabled', Value => 0 );
is(
    $Directory->MembershipGrant(
        Subject => $Subject, TenantID => $Tenant, MemberUserID => 1, Role => $Role, UserID => 1,
    )->{Error},
    'AUDIT_WRITE_FAILED',
    'membership grant fails closed when its audit event cannot be written',
);
$DB->Prepare(
    SQL => 'SELECT COUNT(*) FROM d724_tenant_agent_role WHERE tenant_id = ? AND user_id = 1 AND role_name = ?',
    Bind => [ \$Tenant, \$Role ],
);
my ($MembershipCount) = $DB->FetchrowArray();
is( $MembershipCount, 0, 'failed audited grant is rolled back completely' );

$Helper->ConfigSettingChange( Key => 'D724::Audit::Enabled', Value => 1 );
my $Grant = $Directory->MembershipGrant(
    Subject => $Subject, TenantID => $Tenant, MemberUserID => 1, Role => $Role, UserID => 1,
);
ok( $Grant->{Success}, 'membership grant succeeds after audit recovers' );
is( $Grant->{Data}->{Version}, 1, 'retried grant starts at version one' );

$Helper->ConfigSettingChange( Key => 'D724::Audit::Enabled', Value => 0 );
is(
    $Directory->MembershipRevoke(
        Subject => $Subject, TenantID => $Tenant, MemberUserID => 1, Role => $Role, UserID => 1,
    )->{Error},
    'AUDIT_WRITE_FAILED',
    'membership revoke fails closed when its audit event cannot be written',
);
$DB->Prepare(
    SQL => 'SELECT status, version FROM d724_tenant_agent_role WHERE tenant_id = ? AND user_id = 1 AND role_name = ?',
    Bind => [ \$Tenant, \$Role ], Limit => 1,
);
my ( $MembershipStatus, $MembershipVersion ) = $DB->FetchrowArray();
is( $MembershipStatus, 'active', 'failed audited revoke restores active membership' );
is( $MembershipVersion, 1, 'failed audited revoke restores membership version' );

$Helper->ConfigSettingChange( Key => 'D724::Audit::Enabled', Value => 1 );
my $Revoke = $Directory->MembershipRevoke(
    Subject => $Subject, TenantID => $Tenant, MemberUserID => 1, Role => $Role, UserID => 1,
);
ok( $Revoke->{Success}, 'membership revoke succeeds after audit recovers' );
is( $Revoke->{Data}->{Version}, 2, 'retried revoke advances exactly one version' );
my $AuditEvents = $Audit->List( Subject => $Subject, TenantID => $Tenant, Limit => 100 );
is(
    [ map { $_->{Action} } @{ $AuditEvents->{Data} } ],
    [qw(tenant.created tenant.membership.granted tenant.membership.revoked)],
    'failed mutations leave no orphan event and retries form one canonical audit chain',
);
ok( $Audit->Verify( Subject => $Subject, TenantID => $Tenant )->{Valid}, 'rollback fixture audit chain verifies' );

ok( $DB->Do( SQL => 'DELETE FROM d724_audit_event WHERE tenant_id = ?', Bind => [ \$Tenant ] ), 'audit events are cleaned up' );
ok( $DB->Do( SQL => 'DELETE FROM d724_audit_head WHERE tenant_id = ?', Bind => [ \$Tenant ] ), 'audit head is cleaned up' );
ok( $DB->Do( SQL => 'DELETE FROM d724_tenant_agent_role WHERE tenant_id = ?', Bind => [ \$Tenant ] ), 'membership fixture is cleaned up' );
ok( $DB->Do( SQL => 'DELETE FROM d724_tenant WHERE key_name = ?', Bind => [ \$Tenant ] ), 'tenant fixture is cleaned up' );
done_testing;
