# --
# D724 ESM is an enterprise service management platform based on OTOBO.
# Copyright (C) 2026 Data Market Bilgi Hizmetleri A.S.
# SPDX-License-Identifier: GPL-3.0-only
# --

use v5.24;
use strict;
use warnings;
use utf8;
use Test2::V0;
use Kernel::System::UnitTest::RegisterOM;

$Kernel::OM->ObjectParamAdd( 'Kernel::System::UnitTest::Helper' => { RestoreDatabase => 1 } );
my $Helper = $Kernel::OM->Get('Kernel::System::UnitTest::Helper');
my $Config = $Kernel::OM->Get('Kernel::Config');
$Helper->ConfigSettingChange( Key => 'D724::TenantGuard::Enabled', Value => 1 );
$Helper->ConfigSettingChange( Key => 'D724::TenantGuard::AllowPlatformAdmin', Value => 1 );

my $Directory = $Kernel::OM->Get('Kernel::System::D724::TenantDirectory');
my $Platform = { ID => 'platform-test', Roles => ['platform_admin'], TenantIDs => ['bootstrap'] };
my $Suffix = $Helper->GetRandomID();
my $TenantA = "directory-a-$Suffix";
my $TenantB = "directory-b-$Suffix";

ok(
    $Directory->TenantCreate( Subject => $Platform, TenantID => $TenantA, Name => 'Directory A', UserID => 1 )->{Success},
    'platform administrator creates tenant A when emergency platform access is enabled',
);
ok(
    $Directory->TenantCreate( Subject => $Platform, TenantID => $TenantB, Name => 'Directory B', UserID => 1 )->{Success},
    'platform administrator creates tenant B',
);
is(
    $Directory->TenantCreate( Subject => $Platform, TenantID => $TenantA, Name => 'Duplicate', UserID => 1 )->{Error},
    'TENANT_EXISTS',
    'tenant identifier is unique',
);

my $AdminA = { ID => 'admin-a', TenantIDs => [$TenantA], RoleBindings => { $TenantA => ['tenant_admin'] } };
my $AdminB = { ID => 'admin-b', TenantIDs => [$TenantB], RoleBindings => { $TenantB => ['tenant_admin'] } };
ok(
    $Directory->MembershipGrant(
        Subject => $AdminA, TenantID => $TenantA, MemberUserID => 1, Role => 'tenant_admin', UserID => 1,
    )->{Success},
    'tenant A administrator grants tenant A role',
);
ok(
    $Directory->MembershipGrant(
        Subject => $AdminB, TenantID => $TenantB, MemberUserID => 1, Role => 'requester', UserID => 1,
    )->{Success},
    'tenant B administrator grants tenant B requester role',
);
is(
    $Directory->MembershipGrant(
        Subject => $AdminA, TenantID => $TenantB, MemberUserID => 1, Role => 'tenant_admin', UserID => 1,
    )->{Error},
    'FORBIDDEN',
    'tenant A administrator cannot grant roles in tenant B',
);
is(
    $Directory->MembershipGrant(
        Subject => $AdminA, TenantID => $TenantA, MemberUserID => 1, Role => 'platform_admin', UserID => 1,
    )->{Error},
    'ROLE_INVALID',
    'platform administrator cannot be granted as a tenant role',
);

my $Context = $Directory->ContextGet( UserID => 1 );
ok( $Context->{Success}, 'active memberships resolve agent context' );
is( $Context->{Subject}->{RoleBindings}->{$TenantA}, ['tenant_admin'], 'tenant A admin role is bound to tenant A' );
is( $Context->{Subject}->{RoleBindings}->{$TenantB}, ['requester'], 'tenant B requester role is bound to tenant B' );
is(
    $Kernel::OM->Get('Kernel::System::D724::TenantGuard')->DecisionGet(
        Subject => $Context->{Subject}, Resource => { TenantID => $TenantB }, Action => 'tenant.manage',
    )->{Reason},
    'DENY_ROLE_NOT_GRANTED',
    'resolved directory context prevents cross-tenant privilege bleed',
);

my $Updated = $Directory->TenantUpdate(
    Subject => $AdminA, TenantID => $TenantA, Name => 'Directory A Updated',
    ExpectedVersion => 1, UserID => 1,
);
is( $Updated->{Data}->{Version}, 2, 'tenant update increments optimistic version' );
is(
    $Directory->TenantUpdate(
        Subject => $AdminA, TenantID => $TenantA, Name => 'Stale', ExpectedVersion => 1, UserID => 1,
    )->{Error},
    'VERSION_CONFLICT',
    'stale tenant update is rejected',
);

ok(
    $Directory->MembershipRevoke(
        Subject => $AdminB, TenantID => $TenantB, MemberUserID => 1, Role => 'requester', UserID => 1,
    )->{Success},
    'tenant membership role can be revoked',
);
my $AfterRevoke = $Directory->ContextGet( UserID => 1 );
ok( !exists $AfterRevoke->{Subject}->{RoleBindings}->{$TenantB}, 'revoked role disappears from context' );
is(
    $Directory->Bootstrap( Confirm => 0, TenantID => 'bootstrap-test', Name => 'Bootstrap', UserID => 1 )->{Error},
    'CONFIRMATION_REQUIRED',
    'bootstrap requires explicit confirmation',
);
is(
    $Directory->Bootstrap( Confirm => 1, TenantID => 'bootstrap-test', Name => 'Bootstrap', UserID => 1 )->{Error},
    'ALREADY_BOOTSTRAPPED',
    'bootstrap is impossible after a tenant exists',
);

done_testing;
