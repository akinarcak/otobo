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

my $Guard        = $Kernel::OM->Get('Kernel::System::D724::TenantGuard');
my $ConfigObject = $Kernel::OM->Get('Kernel::Config');

sub Decision {
    my (%Param) = @_;

    return $Guard->DecisionGet(
        Subject => exists $Param{Subject} ? $Param{Subject} : {
            ID        => 'user-1',
            TenantIDs => $Param{SubjectTenantIDs} // ['tenant-a'],
            Roles     => $Param{Roles} // ['requester'],
        },
        Resource => exists $Param{Resource} ? $Param{Resource} : {
            TenantID => $Param{ResourceTenantID} // 'tenant-a',
        },
        Action => $Param{Action} // 'case.read',
    );
}

my @Matrix = (
    [ 'requester reads own case',             ['requester'],     'case.read',      'tenant-a', 1, 'ALLOW_ROLE_ACTION' ],
    [ 'requester creates own case',           ['requester'],     'case.create',    'tenant-a', 1, 'ALLOW_ROLE_ACTION' ],
    [ 'requester cannot update case',         ['requester'],     'case.update',    'tenant-a', 0, 'DENY_ROLE_NOT_GRANTED' ],
    [ 'agent updates own case',               ['agent'],         'case.update',    'tenant-a', 1, 'ALLOW_ROLE_ACTION' ],
    [ 'agent cannot delete case',             ['agent'],         'case.delete',    'tenant-a', 0, 'DENY_ROLE_NOT_GRANTED' ],
    [ 'service owner deletes own case',       ['service_owner'], 'case.delete',    'tenant-a', 1, 'ALLOW_ROLE_ACTION' ],
    [ 'auditor reads audit data',             ['auditor'],       'audit.read',     'tenant-a', 1, 'ALLOW_ROLE_ACTION' ],
    [ 'auditor cannot update case',           ['auditor'],       'case.update',    'tenant-a', 0, 'DENY_ROLE_NOT_GRANTED' ],
    [ 'automation assigns own case',          ['automation'],    'case.assign',    'tenant-a', 1, 'ALLOW_ROLE_ACTION' ],
    [ 'automation cannot delete case',        ['automation'],    'case.delete',    'tenant-a', 0, 'DENY_ROLE_NOT_GRANTED' ],
    [ 'tenant admin manages own tenant',      ['tenant_admin'],  'tenant.manage',  'tenant-a', 1, 'ALLOW_ROLE_ACTION' ],
    [ 'tenant admin cannot cross tenant',     ['tenant_admin'],  'tenant.manage',  'tenant-b', 0, 'DENY_CROSS_TENANT' ],
    [ 'requester cannot cross tenant',        ['requester'],     'case.read',      'tenant-b', 0, 'DENY_CROSS_TENANT' ],
    [ 'tenant IDs are case sensitive',        ['agent'],         'case.read',      'Tenant-A', 0, 'DENY_CROSS_TENANT' ],
    [ 'unknown role has no grant',            ['unknown'],       'case.read',      'tenant-a', 0, 'DENY_ROLE_NOT_GRANTED' ],
    [ 'mixed roles use an explicit grant',    ['auditor','agent'],'case.update',   'tenant-a', 1, 'ALLOW_ROLE_ACTION' ],
);

for my $Case (@Matrix) {
    my ( $Name, $Roles, $Action, $ResourceTenantID, $Allowed, $Reason ) = @{$Case};
    my $Decision = Decision(
        Roles            => $Roles,
        Action           => $Action,
        ResourceTenantID => $ResourceTenantID,
    );
    is( $Decision->{Allowed}, $Allowed, "$Name: allowed" );
    is( $Decision->{Reason}, $Reason, "$Name: reason" );
    is( $Decision->{PolicyVersion}, '1.0.0', "$Name: policy version" );
}

is(
    Decision( Action => 'case.fly' )->{Reason},
    'DENY_ACTION_UNKNOWN',
    'unknown actions are denied',
);
is(
    Decision( Action => q{} )->{Reason},
    'DENY_ACTION_MISSING',
    'missing action is denied',
);
is(
    Decision( Subject => undef )->{Reason},
    'DENY_SUBJECT_MISSING',
    'missing subject is denied',
);
is(
    Decision( Subject => { TenantIDs => ['tenant-a'], Roles => ['agent'] } )->{Reason},
    'DENY_SUBJECT_ID_MISSING',
    'missing subject ID is denied',
);
is(
    Decision( SubjectTenantIDs => [] )->{Reason},
    'DENY_SUBJECT_TENANT_MISSING',
    'empty subject tenant scope is denied',
);
is(
    Decision( Roles => [] )->{Reason},
    'DENY_SUBJECT_ROLES_MISSING',
    'empty role list is denied',
);
is(
    Decision( Resource => {} )->{Reason},
    'DENY_RESOURCE_TENANT_MISSING',
    'missing resource tenant is denied',
);
is(
    Decision( ResourceTenantID => ' tenant-a' )->{Reason},
    'DENY_TENANT_IDENTIFIER_INVALID',
    'ambiguous tenant identifiers are denied',
);

my $PlatformDenied = Decision(
    Roles            => ['platform_admin'],
    ResourceTenantID => 'tenant-b',
);
is( $PlatformDenied->{Reason}, 'DENY_CROSS_TENANT', 'platform admin bypass is disabled by default' );

{
    local $ConfigObject->{'D724::TenantGuard::AllowPlatformAdmin'} = 1;
    my $PlatformAllowed = Decision(
        Roles            => ['platform_admin'],
        ResourceTenantID => 'tenant-b',
    );
    ok( $PlatformAllowed->{Allowed}, 'explicit emergency platform admin bypass works' );
    is( $PlatformAllowed->{Reason}, 'ALLOW_PLATFORM_ADMIN', 'platform bypass is auditable' );
}

my $Scope = $Guard->ScopeGet(
    Subject => {
        ID        => 'user-1',
        Roles     => ['agent'],
        TenantIDs => [ 'tenant-b', 'tenant-a', 'tenant-a' ],
    },
);
ok( $Scope->{Success}, 'valid tenant scope succeeds' );
is( $Scope->{TenantIDs}, [ 'tenant-a', 'tenant-b' ], 'tenant scope is unique and sorted' );
ok( !$Scope->{Unrestricted}, 'ordinary scope is never unrestricted' );

my $InvalidScope = $Guard->ScopeGet(
    Subject => {
        ID        => 'user-1',
        Roles     => ['agent'],
        TenantIDs => ['bad tenant'],
    },
);
ok( !$InvalidScope->{Success}, 'invalid tenant scope fails closed' );
is( $InvalidScope->{TenantIDs}, [], 'invalid scope returns no tenants' );

is(
    $Guard->ScopeGet(
        Subject => {
            Roles     => ['agent'],
            TenantIDs => ['tenant-a'],
        },
    )->{Reason},
    'DENY_SUBJECT_ID_MISSING',
    'scope without subject ID fails closed',
);
is(
    $Guard->ScopeGet(
        Subject => {
            ID        => 'user-1',
            TenantIDs => ['tenant-a'],
        },
    )->{Reason},
    'DENY_SUBJECT_ROLES_MISSING',
    'scope without roles fails closed',
);
is(
    $Guard->ScopeGet(
        Subject => {
            ID        => 'user-1',
            Roles     => ['unknown'],
            TenantIDs => ['tenant-a'],
        },
    )->{Reason},
    'DENY_ROLE_NOT_GRANTED',
    'scope with only unknown roles fails closed',
);

{
    local $ConfigObject->{'D724::TenantGuard::AllowPlatformAdmin'} = 1;
    my $PlatformScope = $Guard->ScopeGet(
        Subject => {
            ID        => 'platform-1',
            Roles     => ['platform_admin'],
            TenantIDs => ['tenant-a'],
        },
    );
    ok( $PlatformScope->{Success}, 'enabled platform scope succeeds' );
    ok( $PlatformScope->{Unrestricted}, 'enabled platform scope is explicitly unrestricted' );
    is( $PlatformScope->{Reason}, 'ALLOW_PLATFORM_ADMIN', 'unrestricted scope is auditable' );
}

{
    local $ConfigObject->{'D724::TenantGuard::Enabled'} = 0;
    is( Decision()->{Reason}, 'DENY_POLICY_DISABLED', 'disabled policy fails closed' );
    ok(
        !$Guard->ScopeGet(
            Subject => {
                ID        => 'user-1',
                Roles     => ['agent'],
                TenantIDs => ['tenant-a'],
            },
        )->{Success},
        'disabled scope fails closed',
    );
}

done_testing;
