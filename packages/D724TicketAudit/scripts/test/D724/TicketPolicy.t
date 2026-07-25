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
my $DB     = $Kernel::OM->Get('Kernel::System::DB');
my $Ticket = $Kernel::OM->Get('Kernel::System::Ticket');
my $Policy = $Kernel::OM->Get('Kernel::System::D724::TicketPolicy');
my $Suffix = lc $Helper->GetRandomID();
my $TenantA = "policy-a-$Suffix";
my $TenantB = "policy-b-$Suffix";

$Helper->ConfigSettingChange( Key => 'D724::TicketPolicy::Enabled', Value => 0 );
$Helper->ConfigSettingChange( Key => 'D724::TicketAudit::Enabled', Value => 1 );
$Helper->ConfigSettingChange( Key => 'D724::Audit::Enabled', Value => 1 );
$Helper->ConfigSettingChange( Key => 'D724::TenantGuard::Enabled', Value => 1 );
$Helper->ConfigSettingChange( Key => 'D724::TenantGuard::AllowPlatformAdmin', Value => 0 );

for my $TenantID ( $TenantA, $TenantB ) {
    my @Values = ( $TenantID, "Policy $TenantID", 1, 1 );
    my @Bind = map { \$_ } @Values;
    ok( $DB->Do(
        SQL => "INSERT INTO d724_tenant (key_name, name, status, version, create_time, create_by, change_time, change_by) "
            . "VALUES (?, ?, 'active', 1, current_timestamp, ?, current_timestamp, ?)",
        Bind => \@Bind,
    ), "tenant $TenantID created" );
}

my @RoleA = ( $TenantA, 1, 'agent', 1, 1 );
my @RoleBindA = map { \$_ } @RoleA;
ok( $DB->Do(
    SQL => "INSERT INTO d724_tenant_agent_role (tenant_id, user_id, role_name, status, version, create_time, create_by, change_time, change_by) "
        . "VALUES (?, ?, ?, 'active', 1, current_timestamp, ?, current_timestamp, ?)",
    Bind => \@RoleBindA,
), 'agent one is bound only to tenant A' );

my $QueueID    = $Kernel::OM->Get('Kernel::System::Queue')->QueueLookup( Queue => 'Raw' );
my $StateID    = $Kernel::OM->Get('Kernel::System::State')->StateLookup( State => 'new' );
my $PriorityID = $Kernel::OM->Get('Kernel::System::Priority')->PriorityLookup( Priority => '3 normal' );
my @TicketIDs;
for my $TenantID ( $TenantA, $TenantB ) {
    push @TicketIDs, $Ticket->TicketCreate(
        TN => 'D724POL' . $Helper->GetRandomID(), Title => "Policy ticket $TenantID",
        QueueID => $QueueID, Lock => 'unlock', StateID => $StateID, PriorityID => $PriorityID,
        CustomerID => $TenantID, CustomerUser => "user-$TenantID", OwnerID => 1, UserID => 1,
    );
}
ok( $TicketIDs[0] && $TicketIDs[1], 'cross-tenant ticket fixtures created' );

$Helper->ConfigSettingChange( Key => 'D724::TicketPolicy::Enabled', Value => 1 );

my $Scoped = $Policy->SearchScopeApply( Param => { UserID => 1, Result => 'ARRAY' } );
ok( $Scoped->{Success}, 'agent scope resolves' );
my %ScopedTenant = map { $_ => 1 } @{ $Scoped->{Param}->{CustomerID} };
ok( $ScopedTenant{$TenantA}, 'agent search predicate includes tenant A membership' );
ok( !$ScopedTenant{$TenantB}, 'agent search predicate excludes tenant B' );
is(
    $Policy->SearchScopeApply( Param => { UserID => 1, CustomerID => [$TenantB] } )->{Reason},
    'EMPTY_TENANT_INTERSECTION',
    'cross-tenant requested filter fails closed',
);
is(
    $Policy->SearchScopeApply( Param => { UserID => 1, CustomerIDRaw => $TenantA } )->{Reason},
    'CUSTOMER_ID_RAW_FORBIDDEN',
    'raw customer search bypass is forbidden',
);
is(
    $Policy->SearchScopeApply( Param => { UserID => 999999, Result => 'ARRAY' } )->{Error},
    'FORBIDDEN',
    'unknown agent has no implicit search scope',
);

my @Visible = $Ticket->TicketSearch( UserID => 1, Result => 'ARRAY', Title => 'Policy ticket*' );
is( \@Visible, [ $TicketIDs[0] ], 'core TicketSearch returns only the bound tenant ticket' );
my @CrossTenant = $Ticket->TicketSearch( UserID => 1, Result => 'ARRAY', CustomerID => $TenantB );
is( \@CrossTenant, [], 'core TicketSearch returns no cross-tenant rows' );

ok(
    $Policy->TicketAccessCheck( UserID => 1, TicketID => $TicketIDs[0] )->{Success},
    'single-ticket policy allows same-tenant access',
);
is(
    $Policy->TicketAccessCheck( UserID => 1, TicketID => $TicketIDs[1] )->{Reason},
    'CROSS_TENANT',
    'single-ticket policy denies cross-tenant access',
);
is(
    $Policy->TicketAccessCheck( UserID => 1, TicketID => 999999999 )->{Reason},
    'TICKET_SCOPE_MISSING',
    'unknown or unbound ticket fails closed',
);

my $GICommon = bless {}, 'Kernel::GenericInterface::Operation::Ticket::Common';
{
    package Kernel::GenericInterface::Operation::Ticket::TicketGet;
    sub D724PolicyTestCall { return $_[0]->CheckAccessPermissions( %{ $_[1] } ) }
    package Kernel::GenericInterface::Operation::Ticket::TicketHistoryGet;
    sub D724PolicyTestCall { return $_[0]->CheckAccessPermissions( %{ $_[1] } ) }
    package Kernel::GenericInterface::Operation::Ticket::TicketUpdate;
    sub D724PolicyTestCall { return $_[0]->CheckAccessPermissions( %{ $_[1] } ) }
    package main;
}
my $GICall = { UserID => 1, UserType => 'User', TicketID => $TicketIDs[0] };
ok(
    Kernel::GenericInterface::Operation::Ticket::TicketGet::D724PolicyTestCall( $GICommon, $GICall ),
    'TicketGet caller is mapped to its operation-specific action',
);
ok(
    Kernel::GenericInterface::Operation::Ticket::TicketHistoryGet::D724PolicyTestCall( $GICommon, $GICall ),
    'TicketHistoryGet caller is mapped to its operation-specific action',
);
ok(
    Kernel::GenericInterface::Operation::Ticket::TicketUpdate::D724PolicyTestCall( $GICommon, $GICall ),
    'TicketUpdate caller is mapped to its operation-specific action',
);
ok(
    $GICommon->CheckAccessPermissions( UserID => 1, UserType => 'User', TicketID => $TicketIDs[0], D724Action => 'integration.ticket.get' ),
    'Generic Interface common adapter permits core-authorized same-tenant read',
);
ok(
    !$GICommon->CheckAccessPermissions( UserID => 1, UserType => 'User', TicketID => $TicketIDs[1], D724Action => 'integration.ticket.get' ),
    'Generic Interface common adapter denies cross-tenant get/history/update access',
);
ok(
    $GICommon->CheckAccessPermissions( UserID => 1, UserType => 'User', TicketID => $TicketIDs[0], D724Action => 'integration.ticket.update' ),
    'agent role permits Generic Interface update action',
);
ok(
    !$GICommon->CheckAccessPermissions( UserID => 1, UserType => 'User', TicketID => $TicketIDs[0], D724Action => 'integration.ticket.unknown' ),
    'unknown Generic Interface action fails closed',
);
ok(
    !$GICommon->CheckAccessPermissions( UserID => 1, UserType => 'User', TicketID => $TicketIDs[0] ),
    'unidentified Generic Interface operation fails closed',
);

done_testing;
