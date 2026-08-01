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
my $Helper = $Kernel::OM->Get('Kernel::System::UnitTest::Helper');
my $DB = $Kernel::OM->Get('Kernel::System::DB');
my $Tenant = 'ticket-audit-' . lc $Helper->GetRandomID();
my $OtherTenant = 'ticket-other-' . lc $Helper->GetRandomID();
my $Handle = $DB->Connect();

$Helper->ConfigSettingChange( Key => 'D724::TicketAudit::Enabled', Value => 1 );
$Helper->ConfigSettingChange( Key => 'D724::Audit::Enabled', Value => 1 );
$Helper->ConfigSettingChange( Key => 'D724::TenantGuard::Enabled', Value => 1 );
$Helper->ConfigSettingChange( Key => 'D724::TenantGuard::AllowPlatformAdmin', Value => 1 );
$Handle->commit() if !$Handle->{AutoCommit};
ok( $Handle->{AutoCommit}, 'ticket audit test starts in production-style AutoCommit mode' );

for my $TenantID ( $Tenant, $OtherTenant ) {
    my @Values = ( $TenantID, "Ticket Test $TenantID", 1, 1 );
    my @Bind = map { \$_ } @Values;
    ok( $DB->Do(
        SQL => "INSERT INTO d724_tenant (key_name, name, status, version, create_time, create_by, change_time, change_by) VALUES (?, ?, 'active', 1, current_timestamp, ?, current_timestamp, ?)",
        Bind => \@Bind,
    ), "tenant fixture $TenantID is created" );
}

my $Ticket = $Kernel::OM->Get('Kernel::System::Ticket');
my $QueueID = $Kernel::OM->Get('Kernel::System::Queue')->QueueLookup( Queue => 'Raw' );
my $StateID = $Kernel::OM->Get('Kernel::System::State')->StateLookup( State => 'new' );
my $PriorityID = $Kernel::OM->Get('Kernel::System::Priority')->PriorityLookup( Priority => '3 normal' );
ok( $QueueID && $StateID && $PriorityID, 'core ticket fixture lookups resolve' );

$Helper->ConfigSettingChange( Key => 'D724::TicketAudit::Enabled', Value => 0 );
my $LegacyNumber = 'D724LG' . $Helper->GetRandomID();
my $LegacyTicketID = $Ticket->TicketCreate(
    TN => $LegacyNumber, Title => 'Legacy tenant ticket', QueueID => $QueueID,
    Lock => 'unlock', StateID => $StateID, PriorityID => $PriorityID,
    CustomerID => $Tenant, CustomerUser => 'legacy-ticket-user', OwnerID => 1, UserID => 1,
);
ok( $LegacyTicketID, 'legacy ticket fixture is created before adapter enforcement' );
my $InvalidCustomerID = 'legacy-customer-' . lc $Helper->GetRandomID();
my $InvalidLegacyNumber = 'D724IV' . $Helper->GetRandomID();
my $InvalidLegacyTicketID = $Ticket->TicketCreate(
    TN => $InvalidLegacyNumber, Title => 'Invalid legacy tenant ticket', QueueID => $QueueID,
    Lock => 'unlock', StateID => $StateID, PriorityID => $PriorityID,
    CustomerID => $InvalidCustomerID, CustomerUser => 'invalid-legacy-user', OwnerID => 1, UserID => 1,
);
ok( $InvalidLegacyTicketID, 'legacy ticket with unmapped customer is created before enforcement' );
$Helper->ConfigSettingChange( Key => 'D724::TicketAudit::Enabled', Value => 1 );
$Helper->ConfigSettingChange( Key => 'D724::Audit::Enabled', Value => 0 );
is(
    $Kernel::OM->Get('Kernel::System::D724::TicketAudit')->Backfill(
        Confirm => 1, TenantID => $Tenant, UserID => 1,
    )->{Error},
    'AUDIT_WRITE_FAILED',
    'legacy scope backfill fails closed when audit is unavailable',
);
ok( !$Kernel::OM->Get('Kernel::System::D724::TicketAudit')->ScopeGet( TicketID => $LegacyTicketID ), 'failed legacy backfill leaves no scope row' );
$Helper->ConfigSettingChange( Key => 'D724::Audit::Enabled', Value => 1 );
my $Backfill = $Kernel::OM->Get('Kernel::System::D724::TicketAudit')->Backfill(
    Confirm => 1, TenantID => $Tenant, UserID => 1,
);
is( $Backfill->{Data}->{Backfilled}, 1, 'legacy scope backfill succeeds after audit recovers' );
is( $Kernel::OM->Get('Kernel::System::D724::TicketAudit')->ScopeGet( TicketID => $LegacyTicketID )->{Version}, 1, 'legacy ticket scope starts at version one' );
is(
    $Kernel::OM->Get('Kernel::System::D724::TicketAudit')->AssignLegacy(
        Confirm => 1, TicketID => $InvalidLegacyTicketID, TenantID => $Tenant, UserID => 1,
    )->{Error},
    'CUSTOMER_TENANT_MISMATCH',
    'explicit assignment refuses mismatching customer without replacement confirmation',
);
$Helper->ConfigSettingChange( Key => 'D724::Audit::Enabled', Value => 0 );
is(
    $Kernel::OM->Get('Kernel::System::D724::TicketAudit')->AssignLegacy(
        Confirm => 1, TicketID => $InvalidLegacyTicketID, TenantID => $Tenant, UserID => 1, ReplaceCustomerID => 1,
    )->{Error},
    'AUDIT_WRITE_FAILED',
    'explicit customer replacement rolls back when audit is unavailable',
);
my %InvalidAfterFailure = $Ticket->TicketGet( TicketID => $InvalidLegacyTicketID, DynamicFields => 0, UserID => 1 );
is( $InvalidAfterFailure{CustomerID}, $InvalidCustomerID, 'failed assignment restores original legacy customer ID' );
ok( !$Kernel::OM->Get('Kernel::System::D724::TicketAudit')->ScopeGet( TicketID => $InvalidLegacyTicketID ), 'failed explicit assignment leaves no scope row' );
$Helper->ConfigSettingChange( Key => 'D724::Audit::Enabled', Value => 1 );
my $Assigned = $Kernel::OM->Get('Kernel::System::D724::TicketAudit')->AssignLegacy(
    Confirm => 1, TicketID => $InvalidLegacyTicketID, TenantID => $Tenant, UserID => 1, ReplaceCustomerID => 1,
);
ok( $Assigned->{Success} && $Assigned->{Data}->{CustomerIDReplaced}, 'explicit legacy assignment succeeds with replacement confirmation' );
is( $Kernel::OM->Get('Kernel::System::D724::TicketAudit')->ScopeGet( TicketID => $InvalidLegacyTicketID )->{TenantID}, $Tenant, 'explicit assignment creates immutable tenant scope' );
my %InvalidAfterSuccess = $Ticket->TicketGet( TicketID => $InvalidLegacyTicketID, DynamicFields => 0, UserID => 1 );
is( $InvalidAfterSuccess{CustomerID}, $Tenant, 'explicit assignment updates legacy customer ID inside transaction' );

my $TicketNumber = 'D724TA' . $Helper->GetRandomID();
my $TicketID = $Ticket->TicketCreate(
    TN => $TicketNumber, Title => 'Atomic tenant ticket', QueueID => $QueueID,
    Lock => 'unlock', StateID => $StateID, PriorityID => $PriorityID,
    CustomerID => $Tenant, CustomerUser => 'ticket-test-user', OwnerID => 1, UserID => 1,
);
ok( $TicketID, 'tenant-bound CareOnCloud ticket is created' );
my $Scope = $Kernel::OM->Get('Kernel::System::D724::TicketAudit')->ScopeGet( TicketID => $TicketID );
is( $Scope->{TenantID}, $Tenant, 'ticket gets immutable tenant binding' );
is( $Scope->{Version}, 1, 'new ticket binding starts at version one' );

my $Subject = { ID => 'ticket-auditor', TenantIDs => [$Tenant], RoleBindings => { $Tenant => ['tenant_admin'] } };
my $Audit = $Kernel::OM->Get('Kernel::System::D724::Audit');
my $Events = $Audit->List( Subject => $Subject, TenantID => $Tenant, ObjectType => 'ticket', ObjectID => "$TicketID" );
is( [ map { $_->{Action} } @{ $Events->{Data} } ], ['ticket.created'], 'ticket create emits one normalized event' );

my $OpenStateID = $Kernel::OM->Get('Kernel::System::State')->StateLookup( State => 'open' );
ok( $OpenStateID, 'open state fixture resolves' );
$Helper->ConfigSettingChange( Key => 'D724::Audit::Enabled', Value => 0 );
ok( !$Ticket->TicketStateSet( TicketID => $TicketID, StateID => $OpenStateID, UserID => 1 ), 'state update fails closed when audit is unavailable' );
my %AfterFailure = $Ticket->TicketGet( TicketID => $TicketID, DynamicFields => 0, UserID => 1 );
is( $AfterFailure{StateID}, $StateID, 'failed audited state update rolls ticket state back' );
is( $Kernel::OM->Get('Kernel::System::D724::TicketAudit')->ScopeGet( TicketID => $TicketID )->{Version}, 1, 'failed state update rolls scope version back' );

$Helper->ConfigSettingChange( Key => 'D724::Audit::Enabled', Value => 1 );
ok( $Ticket->TicketStateSet( TicketID => $TicketID, StateID => $OpenStateID, UserID => 1 ), 'same state update succeeds after audit recovers' );
is( $Kernel::OM->Get('Kernel::System::D724::TicketAudit')->ScopeGet( TicketID => $TicketID )->{Version}, 2, 'successful state update advances scope version once' );
ok( $Ticket->TicketTitleUpdate( TicketID => $TicketID, Title => 'Atomic tenant ticket updated', UserID => 1 ), 'ticket title update succeeds' );
is( $Kernel::OM->Get('Kernel::System::D724::TicketAudit')->ScopeGet( TicketID => $TicketID )->{Version}, 3, 'title update advances scope version' );
ok( $Ticket->TicketTitleUpdate( TicketID => $TicketID, Title => 'Atomic tenant ticket updated', UserID => 1 ), 'same title replay succeeds' );
is( $Kernel::OM->Get('Kernel::System::D724::TicketAudit')->ScopeGet( TicketID => $TicketID )->{Version}, 3, 'no-op title replay does not advance scope version' );
ok(
    $Ticket->TicketCustomerSet( TicketID => $TicketID, No => $Tenant, User => 'ticket-test-user-2', UserID => 1 ),
    'customer user can change inside immutable tenant boundary',
);
is( $Kernel::OM->Get('Kernel::System::D724::TicketAudit')->ScopeGet( TicketID => $TicketID )->{Version}, 4, 'customer user update advances scope version' );
my $ArticleBackend = $Kernel::OM->Get('Kernel::System::Ticket::Article')->BackendForChannel( ChannelName => 'Internal' );
is(
    $ArticleBackend->{ArticleStorageModule},
    'Kernel::System::Ticket::Article::Backend::MIMEBase::ArticleStorageDB',
    'acceptance runtime uses transactional database article storage',
);
my %Article = (
    TicketID => $TicketID, SenderType => 'agent', IsVisibleForCustomer => 1,
    From => 'D724 Agent <agent@example.test>', To => 'D724 Customer <customer@example.test>',
    Subject => 'Audited internal article', Body => 'Acceptance body is not copied into the audit event.',
    ContentType => 'text/plain; charset=utf-8', HistoryType => 'AddNote', HistoryComment => 'D724 audit acceptance',
    UserID => 1, NoAgentNotify => 1,
);
$Helper->ConfigSettingChange( Key => 'D724::Audit::Enabled', Value => 0 );
ok( !$ArticleBackend->ArticleCreate(%Article), 'article create fails closed when audit is unavailable' );
is( [ $Kernel::OM->Get('Kernel::System::Ticket::Article')->ArticleList( TicketID => $TicketID ) ], [], 'failed audited article leaves no article row' );
is( $Kernel::OM->Get('Kernel::System::D724::TicketAudit')->ScopeGet( TicketID => $TicketID )->{Version}, 4, 'failed article create rolls scope version back' );
$Helper->ConfigSettingChange( Key => 'D724::Audit::Enabled', Value => 1 );
my $ArticleID = $ArticleBackend->ArticleCreate(%Article);
ok( $ArticleID, 'article create succeeds after audit recovers' );
is( $Kernel::OM->Get('Kernel::System::D724::TicketAudit')->ScopeGet( TicketID => $TicketID )->{Version}, 5, 'successful article advances scope version once' );
my $ArticleEvents = $Audit->List(
    Subject => $Subject, TenantID => $Tenant, ObjectType => 'ticket_article', ObjectID => "$ArticleID",
);
is( [ map { $_->{Action} } @{ $ArticleEvents->{Data} } ], ['ticket.article.created'], 'article emits one normalized audit event' );
ok( !exists $ArticleEvents->{Data}->[0]->{Details}->{body}, 'article body is excluded from audit details' );
ok(
    !$Ticket->TicketCustomerSet( TicketID => $TicketID, No => $OtherTenant, User => 'other-user', UserID => 1 ),
    'ticket cannot be reassigned across tenant boundary',
);
my %AfterCrossTenant = $Ticket->TicketGet( TicketID => $TicketID, DynamicFields => 0, UserID => 1 );
is( $AfterCrossTenant{CustomerID}, $Tenant, 'cross-tenant customer mutation leaves tenant unchanged' );

my $UnscopedNumber = 'D724UN' . $Helper->GetRandomID();
ok( !$Ticket->TicketCreate(
    TN => $UnscopedNumber, Title => 'Unscoped ticket', QueueID => $QueueID,
    Lock => 'unlock', StateID => $StateID, PriorityID => $PriorityID, OwnerID => 1, UserID => 1,
), 'ticket creation without an active tenant fails closed' );
ok( !$Ticket->TicketIDLookup( TicketNumber => $UnscopedNumber, UserID => 1 ), 'tenantless rejection leaves no ticket row' );

$Events = $Audit->List( Subject => $Subject, TenantID => $Tenant, ObjectType => 'ticket', ObjectID => "$TicketID" );
is(
    [ map { $_->{Action} } @{ $Events->{Data} } ],
    [qw(ticket.created ticket.state.updated ticket.title.updated ticket.customer.updated)],
    'failed/no-op updates leave no orphan event and successful mutations emit one event each',
);
like( $Events->{Data}->[3]->{ToState}, qr{\Asha256:[0-9a-f]{40}\z}, 'long customer state uses deterministic hash token' );
is(
    $Events->{Data}->[3]->{Details}->{to_value}, "$Tenant|ticket-test-user-2",
    'full customer mutation value remains available in normalized details',
);
ok( $Audit->Verify( Subject => $Subject, TenantID => $Tenant )->{Valid}, 'ticket tenant audit chain verifies' );

ok( $Ticket->TicketDelete( TicketID => $TicketID, UserID => 1 ), 'ticket fixture is removed' );
ok( $Ticket->TicketDelete( TicketID => $LegacyTicketID, UserID => 1 ), 'legacy ticket fixture is removed' );
ok( $Ticket->TicketDelete( TicketID => $InvalidLegacyTicketID, UserID => 1 ), 'invalid legacy ticket fixture is removed' );
ok( $DB->Do( SQL => 'DELETE FROM d724_ticket_scope WHERE ticket_id = ?', Bind => [ \$TicketID ] ), 'ticket scope fixture is removed' );
ok( $DB->Do( SQL => 'DELETE FROM d724_ticket_scope WHERE ticket_id = ?', Bind => [ \$LegacyTicketID ] ), 'legacy ticket scope fixture is removed' );
ok( $DB->Do( SQL => 'DELETE FROM d724_ticket_scope WHERE ticket_id = ?', Bind => [ \$InvalidLegacyTicketID ] ), 'explicit legacy ticket scope fixture is removed' );
ok( $DB->Do( SQL => 'DELETE FROM d724_audit_event WHERE tenant_id = ?', Bind => [ \$Tenant ] ), 'ticket audit events are removed' );
ok( $DB->Do( SQL => 'DELETE FROM d724_audit_head WHERE tenant_id = ?', Bind => [ \$Tenant ] ), 'ticket audit head is removed' );
for my $TenantID ( $Tenant, $OtherTenant ) {
    ok( $DB->Do( SQL => 'DELETE FROM d724_tenant WHERE key_name = ?', Bind => [ \$TenantID ] ), "tenant fixture $TenantID is removed" );
}
done_testing;
