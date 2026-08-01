# --
# CareOnCloud ESM enterprise service management platform.
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
    [ 'automation executes tenant job',       ['automation'],    'automation.execute', 'tenant-a', 1, 'ALLOW_ROLE_ACTION' ],
    [ 'requester cannot execute tenant job',  ['requester'],     'automation.execute', 'tenant-a', 0, 'DENY_ROLE_NOT_GRANTED' ],
    [ 'automation cannot delete case',        ['automation'],    'case.delete',    'tenant-a', 0, 'DENY_ROLE_NOT_GRANTED' ],
    [ 'tenant admin manages own tenant',      ['tenant_admin'],  'tenant.manage',  'tenant-a', 1, 'ALLOW_ROLE_ACTION' ],
    [ 'tenant admin manages identity trust',  ['tenant_admin'],  'identity.manage','tenant-a', 1, 'ALLOW_ROLE_ACTION' ],
    [ 'agent cannot manage identity trust',   ['agent'],         'identity.manage','tenant-a', 0, 'DENY_ROLE_NOT_GRANTED' ],
    [ 'tenant admin provisions SCIM',         ['tenant_admin'],  'scim.provision','tenant-a', 1, 'ALLOW_ROLE_ACTION' ],
    [ 'agent cannot provision SCIM',          ['agent'],         'scim.provision','tenant-a', 0, 'DENY_ROLE_NOT_GRANTED' ],
    [ 'agent reads tenant CMDB',              ['agent'],         'cmdb.read',     'tenant-a', 1, 'ALLOW_ROLE_ACTION' ],
    [ 'tenant admin manages CMDB',            ['tenant_admin'],  'cmdb.manage',   'tenant-a', 1, 'ALLOW_ROLE_ACTION' ],
    [ 'agent cannot manage CMDB',             ['agent'],         'cmdb.manage',   'tenant-a', 0, 'DENY_ROLE_NOT_GRANTED' ],
    [ 'requester cannot read internal CMDB',  ['requester'],     'cmdb.read',     'tenant-a', 0, 'DENY_ROLE_NOT_GRANTED' ],
    [ 'auditor reads tenant report',          ['auditor'],       'report.read',     'tenant-a', 1, 'ALLOW_ROLE_ACTION' ],
    [ 'service owner exports report',         ['service_owner'], 'report.export',   'tenant-a', 1, 'ALLOW_ROLE_ACTION' ],
    [ 'agent cannot export report',           ['agent'],         'report.export',   'tenant-a', 0, 'DENY_ROLE_NOT_GRANTED' ],
    [ 'requester searches own tenant',        ['requester'],     'search.read',     'tenant-a', 1, 'ALLOW_ROLE_ACTION' ],
    [ 'agent cannot search another tenant',   ['agent'],         'search.read',     'tenant-b', 0, 'DENY_CROSS_TENANT' ],
    [ 'requester can use GI ticket get',      ['requester'],     'integration.ticket.get', 'tenant-a', 1, 'ALLOW_ROLE_ACTION' ],
    [ 'requester can use GI history',         ['requester'],     'integration.ticket.history', 'tenant-a', 1, 'ALLOW_ROLE_ACTION' ],
    [ 'requester cannot use GI update',       ['requester'],     'integration.ticket.update', 'tenant-a', 0, 'DENY_ROLE_NOT_GRANTED' ],
    [ 'auditor cannot use GI update',         ['auditor'],       'integration.ticket.update', 'tenant-a', 0, 'DENY_ROLE_NOT_GRANTED' ],
    [ 'agent can use GI update',              ['agent'],         'integration.ticket.update', 'tenant-a', 1, 'ALLOW_ROLE_ACTION' ],
    [ 'agent GI get cannot cross tenant',     ['agent'],         'integration.ticket.get', 'tenant-b', 0, 'DENY_CROSS_TENANT' ],
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
    is( $Decision->{PolicyVersion}, '1.8.0', "$Name: policy version" );
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

my $BoundSubject = {
    ID           => 'multi-tenant-agent',
    TenantIDs    => [ 'tenant-a', 'tenant-b' ],
    RoleBindings => {
        'tenant-a' => ['tenant_admin'],
        'tenant-b' => ['requester'],
    },
};
my $BoundAdminA = $Guard->DecisionGet(
    Subject => $BoundSubject, Resource => { TenantID => 'tenant-a' }, Action => 'catalog.manage',
);
ok( $BoundAdminA->{Allowed}, 'tenant-bound admin manages only its assigned tenant' );
is( $BoundAdminA->{MatchedRole}, 'tenant_admin', 'tenant-bound decision reports matched role' );
is(
    $Guard->DecisionGet(
        Subject => $BoundSubject, Resource => { TenantID => 'tenant-b' }, Action => 'catalog.manage',
    )->{Reason},
    'DENY_ROLE_NOT_GRANTED',
    'admin privilege from tenant A never bleeds into tenant B',
);
ok(
    $Guard->DecisionGet(
        Subject => $BoundSubject, Resource => { TenantID => 'tenant-b' }, Action => 'catalog.read',
    )->{Allowed},
    'tenant B requester grant still applies in tenant B',
);
is(
    $Guard->ScopeGet( Subject => $BoundSubject )->{TenantIDs},
    [ 'tenant-a', 'tenant-b' ],
    'scope derives all tenant role bindings',
);
is(
    $Guard->DecisionGet(
        Subject => { %{$BoundSubject}, TenantIDs => ['tenant-a'] },
        Resource => { TenantID => 'tenant-a' }, Action => 'catalog.read',
    )->{Reason},
    'DENY_TENANT_SCOPE_MISMATCH',
    'declared tenant scope cannot omit a role binding',
);
is(
    $Guard->ScopeGet( Subject => { ID => 'empty-bindings', RoleBindings => {} } )->{Reason},
    'DENY_ROLE_BINDINGS_EMPTY',
    'empty role bindings fail closed',
);
is(
    $Guard->DecisionGet(
        Subject => { ID => 'bad-bindings', RoleBindings => { 'tenant-a' => 'tenant_admin' } },
        Resource => { TenantID => 'tenant-a' }, Action => 'catalog.read',
    )->{Reason},
    'DENY_ROLE_BINDING_INVALID',
    'malformed role binding fails closed',
);

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
