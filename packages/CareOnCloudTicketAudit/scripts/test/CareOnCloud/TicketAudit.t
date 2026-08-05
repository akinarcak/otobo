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

$Helper->ConfigSettingChange( Key => 'CareOnCloud::TicketAudit::Enabled', Value => 1 );
$Helper->ConfigSettingChange( Key => 'CareOnCloud::Audit::Enabled', Value => 1 );
$Helper->ConfigSettingChange( Key => 'CareOnCloud::TenantGuard::Enabled', Value => 1 );
$Helper->ConfigSettingChange( Key => 'CareOnCloud::TenantGuard::AllowPlatformAdmin', Value => 1 );
$Handle->commit() if !$Handle->{AutoCommit};
ok( $Handle->{AutoCommit}, 'ticket audit test starts in production-style AutoCommit mode' );

for my $TenantID ( $Tenant, $OtherTenant ) {
    my @Values = ( $TenantID, "Ticket Test $TenantID", 1, 1 );
    my @Bind = map { \$_ } @Values;
    ok( $DB->Do(
        SQL => "INSERT INTO careoncloud_tenant (key_name, name, status, version, create_time, create_by, change_time, change_by) VALUES (?, ?, 'active', 1, current_timestamp, ?, current_timestamp, ?)",
        Bind => \@Bind,
    ), "tenant fixture $TenantID is created" );
}

my $Ticket = $Kernel::OM->Get('Kernel::System::Ticket');
my $ServiceObject = $Kernel::OM->Get('Kernel::System::Service');
my $SLAObject = $Kernel::OM->Get('Kernel::System::SLA');
my $QueueID = $Kernel::OM->Get('Kernel::System::Queue')->QueueLookup( Queue => 'Raw' );
my $StateID = $Kernel::OM->Get('Kernel::System::State')->StateLookup( State => 'new' );
my $PriorityID = $Kernel::OM->Get('Kernel::System::Priority')->PriorityLookup( Priority => '3 normal' );
ok( $QueueID && $StateID && $PriorityID, 'core ticket fixture lookups resolve' );
my $ServiceID = $ServiceObject->ServiceAdd(
    Name => 'Ticket audit service ' . $Helper->GetRandomID(), Comment => 'ticket audit fixture', ValidID => 1, UserID => 1,
);
ok( $ServiceID, 'ticket audit service fixture is created' );
my $SLAID = $SLAObject->SLAAdd(
    Name => 'Ticket audit SLA ' . $Helper->GetRandomID(), ServiceIDs => [$ServiceID], ValidID => 1,
    Comment => 'ticket audit fixture', UserID => 1,
);
ok( $SLAID, 'ticket audit SLA fixture is created' );

$Helper->ConfigSettingChange( Key => 'CareOnCloud::TicketAudit::Enabled', Value => 0 );
my $LegacyNumber = 'CareOnCloudLG' . $Helper->GetRandomID();
my $LegacyTicketID = $Ticket->TicketCreate(
    TN => $LegacyNumber, Title => 'Legacy tenant ticket', QueueID => $QueueID,
    Lock => 'unlock', StateID => $StateID, PriorityID => $PriorityID,
    CustomerID => $Tenant, CustomerUser => 'legacy-ticket-user', OwnerID => 1, UserID => 1,
);
ok( $LegacyTicketID, 'legacy ticket fixture is created before adapter enforcement' );
my $InvalidCustomerID = 'legacy-customer-' . lc $Helper->GetRandomID();
my $InvalidLegacyNumber = 'CareOnCloudIV' . $Helper->GetRandomID();
my $InvalidLegacyTicketID = $Ticket->TicketCreate(
    TN => $InvalidLegacyNumber, Title => 'Invalid legacy tenant ticket', QueueID => $QueueID,
    Lock => 'unlock', StateID => $StateID, PriorityID => $PriorityID,
    CustomerID => $InvalidCustomerID, CustomerUser => 'invalid-legacy-user', OwnerID => 1, UserID => 1,
);
ok( $InvalidLegacyTicketID, 'legacy ticket with unmapped customer is created before enforcement' );
$Helper->ConfigSettingChange( Key => 'CareOnCloud::TicketAudit::Enabled', Value => 1 );
$Helper->ConfigSettingChange( Key => 'CareOnCloud::Audit::Enabled', Value => 0 );
is(
    $Kernel::OM->Get('Kernel::System::CareOnCloud::TicketAudit')->Backfill(
        Confirm => 1, TenantID => $Tenant, UserID => 1,
    )->{Error},
    'AUDIT_WRITE_FAILED',
    'legacy scope backfill fails closed when audit is unavailable',
);
ok( !$Kernel::OM->Get('Kernel::System::CareOnCloud::TicketAudit')->ScopeGet( TicketID => $LegacyTicketID ), 'failed legacy backfill leaves no scope row' );
$Helper->ConfigSettingChange( Key => 'CareOnCloud::Audit::Enabled', Value => 1 );
my $Backfill = $Kernel::OM->Get('Kernel::System::CareOnCloud::TicketAudit')->Backfill(
    Confirm => 1, TenantID => $Tenant, UserID => 1,
);
is( $Backfill->{Data}->{Backfilled}, 1, 'legacy scope backfill succeeds after audit recovers' );
is( $Kernel::OM->Get('Kernel::System::CareOnCloud::TicketAudit')->ScopeGet( TicketID => $LegacyTicketID )->{Version}, 1, 'legacy ticket scope starts at version one' );
is(
    $Kernel::OM->Get('Kernel::System::CareOnCloud::TicketAudit')->AssignLegacy(
        Confirm => 1, TicketID => $InvalidLegacyTicketID, TenantID => $Tenant, UserID => 1,
    )->{Error},
    'CUSTOMER_TENANT_MISMATCH',
    'explicit assignment refuses mismatching customer without replacement confirmation',
);
$Helper->ConfigSettingChange( Key => 'CareOnCloud::Audit::Enabled', Value => 0 );
is(
    $Kernel::OM->Get('Kernel::System::CareOnCloud::TicketAudit')->AssignLegacy(
        Confirm => 1, TicketID => $InvalidLegacyTicketID, TenantID => $Tenant, UserID => 1, ReplaceCustomerID => 1,
    )->{Error},
    'AUDIT_WRITE_FAILED',
    'explicit customer replacement rolls back when audit is unavailable',
);
my %InvalidAfterFailure = $Ticket->TicketGet( TicketID => $InvalidLegacyTicketID, DynamicFields => 0, UserID => 1 );
is( $InvalidAfterFailure{CustomerID}, $InvalidCustomerID, 'failed assignment restores original legacy customer ID' );
ok( !$Kernel::OM->Get('Kernel::System::CareOnCloud::TicketAudit')->ScopeGet( TicketID => $InvalidLegacyTicketID ), 'failed explicit assignment leaves no scope row' );
$Helper->ConfigSettingChange( Key => 'CareOnCloud::Audit::Enabled', Value => 1 );
my $Assigned = $Kernel::OM->Get('Kernel::System::CareOnCloud::TicketAudit')->AssignLegacy(
    Confirm => 1, TicketID => $InvalidLegacyTicketID, TenantID => $Tenant, UserID => 1, ReplaceCustomerID => 1,
);
ok( $Assigned->{Success} && $Assigned->{Data}->{CustomerIDReplaced}, 'explicit legacy assignment succeeds with replacement confirmation' );
is( $Kernel::OM->Get('Kernel::System::CareOnCloud::TicketAudit')->ScopeGet( TicketID => $InvalidLegacyTicketID )->{TenantID}, $Tenant, 'explicit assignment creates immutable tenant scope' );
my %InvalidAfterSuccess = $Ticket->TicketGet( TicketID => $InvalidLegacyTicketID, DynamicFields => 0, UserID => 1 );
is( $InvalidAfterSuccess{CustomerID}, $Tenant, 'explicit assignment updates legacy customer ID inside transaction' );

my $TicketNumber = 'CareOnCloudTA' . $Helper->GetRandomID();
my $TicketID = $Ticket->TicketCreate(
    TN => $TicketNumber, Title => 'Atomic tenant ticket', QueueID => $QueueID,
    Lock => 'unlock', StateID => $StateID, PriorityID => $PriorityID,
    CustomerID => $Tenant, CustomerUser => 'ticket-test-user', OwnerID => 1, UserID => 1,
);
ok( $TicketID, 'tenant-bound CareOnCloud ticket is created' );
my $Scope = $Kernel::OM->Get('Kernel::System::CareOnCloud::TicketAudit')->ScopeGet( TicketID => $TicketID );
is( $Scope->{TenantID}, $Tenant, 'ticket gets immutable tenant binding' );
is( $Scope->{Version}, 1, 'new ticket binding starts at version one' );

my $Subject = { ID => 'ticket-auditor', TenantIDs => [$Tenant], RoleBindings => { $Tenant => ['tenant_admin'] } };
my $Audit = $Kernel::OM->Get('Kernel::System::CareOnCloud::Audit');
my $Events = $Audit->List( Subject => $Subject, TenantID => $Tenant, ObjectType => 'ticket', ObjectID => "$TicketID" );
is( [ map { $_->{Action} } @{ $Events->{Data} } ], ['ticket.created'], 'ticket create emits one normalized event' );

my $OpenStateID = $Kernel::OM->Get('Kernel::System::State')->StateLookup( State => 'open' );
ok( $OpenStateID, 'open state fixture resolves' );
$Helper->ConfigSettingChange( Key => 'CareOnCloud::Audit::Enabled', Value => 0 );
ok( !$Ticket->TicketStateSet( TicketID => $TicketID, StateID => $OpenStateID, UserID => 1 ), 'state update fails closed when audit is unavailable' );
my %AfterFailure = $Ticket->TicketGet( TicketID => $TicketID, DynamicFields => 0, UserID => 1 );
is( $AfterFailure{StateID}, $StateID, 'failed audited state update rolls ticket state back' );
is( $Kernel::OM->Get('Kernel::System::CareOnCloud::TicketAudit')->ScopeGet( TicketID => $TicketID )->{Version}, 1, 'failed state update rolls scope version back' );

$Helper->ConfigSettingChange( Key => 'CareOnCloud::Audit::Enabled', Value => 1 );
ok( $Ticket->TicketStateSet( TicketID => $TicketID, StateID => $OpenStateID, UserID => 1 ), 'same state update succeeds after audit recovers' );
is( $Kernel::OM->Get('Kernel::System::CareOnCloud::TicketAudit')->ScopeGet( TicketID => $TicketID )->{Version}, 2, 'successful state update advances scope version once' );

my %TypeBefore = $Ticket->TicketGet( TicketID => $TicketID, DynamicFields => 0, UserID => 1 );
my %TypeList = $Ticket->TicketTypeList( TicketID => $TicketID, UserID => 1 );
my ($AlternateTypeID) = grep { $_ != $TypeBefore{TypeID} } sort { $a <=> $b } keys %TypeList;
SKIP: {
    skip 'no alternate ticket type is available in this fixture', 5 if !$AlternateTypeID;
    $Helper->ConfigSettingChange( Key => 'CareOnCloud::Audit::Enabled', Value => 0 );
    ok( !$Ticket->TicketTypeSet( TicketID => $TicketID, TypeID => $AlternateTypeID, UserID => 1 ), 'type update fails closed when audit is unavailable' );
    my %TypeAfterFailure = $Ticket->TicketGet( TicketID => $TicketID, DynamicFields => 0, UserID => 1 );
    is( $TypeAfterFailure{TypeID}, $TypeBefore{TypeID}, 'failed audited type update rolls ticket type back' );
    is( $Kernel::OM->Get('Kernel::System::CareOnCloud::TicketAudit')->ScopeGet( TicketID => $TicketID )->{Version}, 2, 'failed type update rolls scope version back' );
    $Helper->ConfigSettingChange( Key => 'CareOnCloud::Audit::Enabled', Value => 1 );
    ok( $Ticket->TicketTypeSet( TicketID => $TicketID, TypeID => $AlternateTypeID, UserID => 1 ), 'type update succeeds after audit recovers' );
    is( $Kernel::OM->Get('Kernel::System::CareOnCloud::TicketAudit')->ScopeGet( TicketID => $TicketID )->{Version}, 3, 'successful type update advances scope version once' );
}

my %ServiceBefore = $Ticket->TicketGet( TicketID => $TicketID, DynamicFields => 0, UserID => 1 );
$Helper->ConfigSettingChange( Key => 'CareOnCloud::Audit::Enabled', Value => 0 );
ok( !$Ticket->TicketServiceSet( TicketID => $TicketID, ServiceID => $ServiceID, UserID => 1 ), 'service update fails closed when audit is unavailable' );
my %ServiceAfterFailure = $Ticket->TicketGet( TicketID => $TicketID, DynamicFields => 0, UserID => 1 );
is( $ServiceAfterFailure{ServiceID} // q{}, $ServiceBefore{ServiceID} // q{}, 'failed audited service update rolls ticket service back' );
is( $Kernel::OM->Get('Kernel::System::CareOnCloud::TicketAudit')->ScopeGet( TicketID => $TicketID )->{Version}, $AlternateTypeID ? 3 : 2, 'failed service update rolls scope version back' );
$Helper->ConfigSettingChange( Key => 'CareOnCloud::Audit::Enabled', Value => 1 );
ok( $Ticket->TicketServiceSet( TicketID => $TicketID, ServiceID => $ServiceID, UserID => 1 ), 'service update succeeds after audit recovers' );
is( $Kernel::OM->Get('Kernel::System::CareOnCloud::TicketAudit')->ScopeGet( TicketID => $TicketID )->{Version}, $AlternateTypeID ? 4 : 3, 'successful service update advances scope version once' );

my %SLABefore = $Ticket->TicketGet( TicketID => $TicketID, DynamicFields => 0, UserID => 1 );
$Helper->ConfigSettingChange( Key => 'CareOnCloud::Audit::Enabled', Value => 0 );
ok( !$Ticket->TicketSLASet( TicketID => $TicketID, SLAID => $SLAID, UserID => 1 ), 'SLA update fails closed when audit is unavailable' );
my %SLAAfterFailure = $Ticket->TicketGet( TicketID => $TicketID, DynamicFields => 0, UserID => 1 );
is( $SLAAfterFailure{SLAID} // q{}, $SLABefore{SLAID} // q{}, 'failed audited SLA update rolls ticket SLA back' );
is( $Kernel::OM->Get('Kernel::System::CareOnCloud::TicketAudit')->ScopeGet( TicketID => $TicketID )->{Version}, $AlternateTypeID ? 4 : 3, 'failed SLA update rolls scope version back' );
$Helper->ConfigSettingChange( Key => 'CareOnCloud::Audit::Enabled', Value => 1 );
ok( $Ticket->TicketSLASet( TicketID => $TicketID, SLAID => $SLAID, UserID => 1 ), 'SLA update succeeds after audit recovers' );
is( $Kernel::OM->Get('Kernel::System::CareOnCloud::TicketAudit')->ScopeGet( TicketID => $TicketID )->{Version}, $AlternateTypeID ? 5 : 4, 'successful SLA update advances scope version once' );

my %PendingBefore = $Ticket->TicketGet( TicketID => $TicketID, DynamicFields => 0, UserID => 1 );
my $PendingAt = '2030-01-02 03:04:05';
$Helper->ConfigSettingChange( Key => 'CareOnCloud::Audit::Enabled', Value => 0 );
ok( !$Ticket->TicketPendingTimeSet( TicketID => $TicketID, String => $PendingAt, UserID => 1 ), 'pending-time update fails closed when audit is unavailable' );
my %PendingAfterFailure = $Ticket->TicketGet( TicketID => $TicketID, DynamicFields => 0, UserID => 1 );
is( $PendingAfterFailure{RealTillTimeNotUsed} // q{}, $PendingBefore{RealTillTimeNotUsed} // q{}, 'failed audited pending-time update rolls ticket value back' );
is( $Kernel::OM->Get('Kernel::System::CareOnCloud::TicketAudit')->ScopeGet( TicketID => $TicketID )->{Version}, $AlternateTypeID ? 5 : 4, 'failed pending-time update rolls scope version back' );
$Helper->ConfigSettingChange( Key => 'CareOnCloud::Audit::Enabled', Value => 1 );
ok( $Ticket->TicketPendingTimeSet( TicketID => $TicketID, String => $PendingAt, UserID => 1 ), 'pending-time update succeeds after audit recovers' );
is( $Kernel::OM->Get('Kernel::System::CareOnCloud::TicketAudit')->ScopeGet( TicketID => $TicketID )->{Version}, $AlternateTypeID ? 6 : 5, 'successful pending-time update advances scope version once' );

ok( $Ticket->TicketTitleUpdate( TicketID => $TicketID, Title => 'Atomic tenant ticket updated', UserID => 1 ), 'ticket title update succeeds' );
is( $Kernel::OM->Get('Kernel::System::CareOnCloud::TicketAudit')->ScopeGet( TicketID => $TicketID )->{Version}, $AlternateTypeID ? 7 : 6, 'title update advances scope version' );
ok( $Ticket->TicketTitleUpdate( TicketID => $TicketID, Title => 'Atomic tenant ticket updated', UserID => 1 ), 'same title replay succeeds' );
is( $Kernel::OM->Get('Kernel::System::CareOnCloud::TicketAudit')->ScopeGet( TicketID => $TicketID )->{Version}, $AlternateTypeID ? 7 : 6, 'no-op title replay does not advance scope version' );
ok(
    $Ticket->TicketCustomerSet( TicketID => $TicketID, No => $Tenant, User => 'ticket-test-user-2', UserID => 1 ),
    'customer user can change inside immutable tenant boundary',
);
is( $Kernel::OM->Get('Kernel::System::CareOnCloud::TicketAudit')->ScopeGet( TicketID => $TicketID )->{Version}, $AlternateTypeID ? 8 : 7, 'customer user update advances scope version' );

$Helper->ConfigSettingChange( Key => 'Ticket::ArchiveSystem', Value => 1 );
$Helper->ConfigSettingChange( Key => 'Ticket::ArchiveSystem::RemoveSeenFlags', Value => 0 );
$Helper->ConfigSettingChange( Key => 'Ticket::ArchiveSystem::RemoveTicketWatchers', Value => 0 );
my $ArchiveVersion = $Kernel::OM->Get('Kernel::System::CareOnCloud::TicketAudit')->ScopeGet( TicketID => $TicketID )->{Version};
my %BeforeArchive = $Ticket->TicketGet( TicketID => $TicketID, DynamicFields => 0, UserID => 1 );
is( $BeforeArchive{ArchiveFlag}, 'n', 'ticket starts outside the archive' );
$Helper->ConfigSettingChange( Key => 'CareOnCloud::Audit::Enabled', Value => 0 );
ok( !$Ticket->TicketArchiveFlagSet( TicketID => $TicketID, ArchiveFlag => 'y', UserID => 1 ), 'archive update fails closed when audit is unavailable' );
my %AfterArchiveFailure = $Ticket->TicketGet( TicketID => $TicketID, DynamicFields => 0, UserID => 1 );
is( $AfterArchiveFailure{ArchiveFlag}, 'n', 'failed audited archive update rolls ticket flag back' );
is(
    $Kernel::OM->Get('Kernel::System::CareOnCloud::TicketAudit')->ScopeGet( TicketID => $TicketID )->{Version},
    $ArchiveVersion,
    'failed archive update rolls scope version back',
);
$Helper->ConfigSettingChange( Key => 'CareOnCloud::Audit::Enabled', Value => 1 );
ok( $Ticket->TicketArchiveFlagSet( TicketID => $TicketID, ArchiveFlag => 'y', UserID => 1 ), 'archive update succeeds after audit recovers' );
my %AfterArchiveSuccess = $Ticket->TicketGet( TicketID => $TicketID, DynamicFields => 0, UserID => 1 );
is( $AfterArchiveSuccess{ArchiveFlag}, 'y', 'successful audited archive update persists ticket flag' );
is(
    $Kernel::OM->Get('Kernel::System::CareOnCloud::TicketAudit')->ScopeGet( TicketID => $TicketID )->{Version},
    $ArchiveVersion + 1,
    'successful archive update advances scope version once',
);
my $ArchiveEvents = $Audit->List( Subject => $Subject, TenantID => $Tenant, ObjectType => 'ticket', ObjectID => "$TicketID" );
is(
    scalar( grep { $_->{Action} eq 'ticket.archive_flag.updated' } @{ $ArchiveEvents->{Data} } ),
    1,
    'archive update emits one normalized audit event',
);

my $UnlockVersion = $Kernel::OM->Get('Kernel::System::CareOnCloud::TicketAudit')->ScopeGet( TicketID => $TicketID )->{Version};
my %BeforeUnlock = $Ticket->TicketGet( TicketID => $TicketID, DynamicFields => 0, UserID => 1 );
$Helper->ConfigSettingChange( Key => 'CareOnCloud::Audit::Enabled', Value => 0 );
ok( !$Ticket->TicketUnlockTimeoutUpdate( TicketID => $TicketID, UnlockTimeout => 1, UserID => 1 ), 'unlock-timeout update fails closed when audit is unavailable' );
my %AfterUnlockFailure = $Ticket->TicketGet( TicketID => $TicketID, DynamicFields => 0, UserID => 1 );
is( $AfterUnlockFailure{UnlockTimeout}, $BeforeUnlock{UnlockTimeout}, 'failed audited unlock-timeout update rolls ticket value back' );
is(
    $Kernel::OM->Get('Kernel::System::CareOnCloud::TicketAudit')->ScopeGet( TicketID => $TicketID )->{Version},
    $UnlockVersion,
    'failed unlock-timeout update rolls scope version back',
);
$Helper->ConfigSettingChange( Key => 'CareOnCloud::Audit::Enabled', Value => 1 );
ok( $Ticket->TicketUnlockTimeoutUpdate( TicketID => $TicketID, UnlockTimeout => 1, UserID => 1 ), 'unlock-timeout update succeeds after audit recovers' );
my %AfterUnlockSuccess = $Ticket->TicketGet( TicketID => $TicketID, DynamicFields => 0, UserID => 1 );
is( $AfterUnlockSuccess{UnlockTimeout}, 1, 'successful audited unlock-timeout update persists value' );
is(
    $Kernel::OM->Get('Kernel::System::CareOnCloud::TicketAudit')->ScopeGet( TicketID => $TicketID )->{Version},
    $UnlockVersion + 1,
    'successful unlock-timeout update advances scope version once',
);
my $UnlockEvents = $Audit->List( Subject => $Subject, TenantID => $Tenant, ObjectType => 'ticket', ObjectID => "$TicketID" );
is(
    scalar( grep { $_->{Action} eq 'ticket.unlock_timeout.updated' } @{ $UnlockEvents->{Data} } ),
    1,
    'direct unlock-timeout update emits one normalized audit event',
);

my $OriginalAuditRecord = \&Kernel::System::CareOnCloud::TicketAudit::_AuditRecord;
my $LockVersion = $Kernel::OM->Get('Kernel::System::CareOnCloud::TicketAudit')->ScopeGet( TicketID => $TicketID )->{Version};
{
    no warnings 'redefine'; ## no critic
    local *Kernel::System::CareOnCloud::TicketAudit::_AuditRecord = sub {
        my ( $Self, %Param ) = @_;
        return { Success => 0, Error => 'INJECTED_TIMEOUT_AUDIT_FAILURE' }
            if ( $Param{Action} // q{} ) eq 'ticket.unlock_timeout.updated';
        return $OriginalAuditRecord->( $Self, %Param );
    };
    ok( !$Ticket->TicketLockSet( TicketID => $TicketID, Lock => 'lock', UserID => 1 ), 'nested unlock-timeout audit failure rolls lock parent back' );
}
my %AfterInjectedLockFailure = $Ticket->TicketGet( TicketID => $TicketID, DynamicFields => 0, UserID => 1 );
is( $AfterInjectedLockFailure{Lock}, 'unlock', 'nested timeout audit failure restores parent lock value' );
is( $AfterInjectedLockFailure{UnlockTimeout}, 1, 'nested timeout audit failure restores lock parent timeout' );
is( $Kernel::OM->Get('Kernel::System::CareOnCloud::TicketAudit')->ScopeGet( TicketID => $TicketID )->{Version}, $LockVersion, 'nested timeout audit failure restores lock parent scope version' );
ok( $Ticket->TicketLockSet( TicketID => $TicketID, Lock => 'lock', UserID => 1 ), 'lock parent succeeds after nested timeout audit recovers' );
my %AfterLockSuccess = $Ticket->TicketGet( TicketID => $TicketID, DynamicFields => 0, UserID => 1 );
is( $AfterLockSuccess{Lock}, 'lock', 'successful lock parent persists lock value' );
isnt( $AfterLockSuccess{UnlockTimeout}, 1, 'successful lock parent persists nested timeout value' );
is( $Kernel::OM->Get('Kernel::System::CareOnCloud::TicketAudit')->ScopeGet( TicketID => $TicketID )->{Version}, $LockVersion + 2, 'successful lock parent advances timeout and lock scope versions consecutively' );
ok( $Ticket->TicketUnlockTimeoutUpdate( TicketID => $TicketID, UnlockTimeout => 1, UserID => 1 ), 'MIMEBase rollback fixture resets unlock timeout through audited direct path' );

my $ArticleBackend = $Kernel::OM->Get('Kernel::System::Ticket::Article')->BackendForChannel( ChannelName => 'Internal' );
is(
    $ArticleBackend->{ArticleStorageModule},
    'Kernel::System::Ticket::Article::Backend::MIMEBase::ArticleStorageDB',
    'acceptance runtime uses transactional database article storage',
);
my %Article = (
    TicketID => $TicketID, SenderType => 'agent', IsVisibleForCustomer => 1,
    From => 'CareOnCloud Agent <agent@example.test>', To => 'CareOnCloud Customer <customer@example.test>',
    Subject => 'Audited internal article', Body => 'Acceptance body is not copied into the audit event.',
    ContentType => 'text/plain; charset=utf-8', HistoryType => 'AddNote', HistoryComment => 'CareOnCloud audit acceptance',
    UserID => 1, NoAgentNotify => 1,
);
my $MIMEVersion = $Kernel::OM->Get('Kernel::System::CareOnCloud::TicketAudit')->ScopeGet( TicketID => $TicketID )->{Version};
$Helper->ConfigSettingChange( Key => 'CareOnCloud::Audit::Enabled', Value => 0 );
ok( !$ArticleBackend->ArticleCreate(%Article), 'article create fails closed when audit is unavailable' );
is( [ $Kernel::OM->Get('Kernel::System::Ticket::Article')->ArticleList( TicketID => $TicketID ) ], [], 'failed audited article leaves no article row' );
my %AfterMIMEFailure = $Ticket->TicketGet( TicketID => $TicketID, DynamicFields => 0, UserID => 1 );
is( $AfterMIMEFailure{UnlockTimeout}, 1, 'failed MIMEBase parent rolls nested unlock-timeout value back' );
is( $Kernel::OM->Get('Kernel::System::CareOnCloud::TicketAudit')->ScopeGet( TicketID => $TicketID )->{Version}, $MIMEVersion, 'failed article create rolls parent and nested scope versions back' );
$Helper->ConfigSettingChange( Key => 'CareOnCloud::Audit::Enabled', Value => 1 );
{
    no warnings 'redefine'; ## no critic
    local *Kernel::System::CareOnCloud::TicketAudit::_AuditRecord = sub {
        my ( $Self, %Param ) = @_;
        return { Success => 0, Error => 'INJECTED_TIMEOUT_AUDIT_FAILURE' }
            if ( $Param{Action} // q{} ) eq 'ticket.unlock_timeout.updated';
        return $OriginalAuditRecord->( $Self, %Param );
    };
    ok( !$ArticleBackend->ArticleCreate(%Article), 'nested unlock-timeout audit failure rolls MIMEBase parent back' );
}
is( [ $Kernel::OM->Get('Kernel::System::Ticket::Article')->ArticleList( TicketID => $TicketID ) ], [], 'nested timeout audit failure leaves no MIMEBase article row' );
my %AfterInjectedMIMEFailure = $Ticket->TicketGet( TicketID => $TicketID, DynamicFields => 0, UserID => 1 );
is( $AfterInjectedMIMEFailure{UnlockTimeout}, 1, 'nested timeout audit failure restores MIMEBase parent timeout' );
is( $Kernel::OM->Get('Kernel::System::CareOnCloud::TicketAudit')->ScopeGet( TicketID => $TicketID )->{Version}, $MIMEVersion, 'nested timeout audit failure restores MIMEBase parent scope version' );
my $ArticleID = $ArticleBackend->ArticleCreate(%Article);
ok( $ArticleID, 'article create succeeds after audit recovers' );
is( $Kernel::OM->Get('Kernel::System::CareOnCloud::TicketAudit')->ScopeGet( TicketID => $TicketID )->{Version}, $MIMEVersion + 2, 'successful MIMEBase parent advances timeout and article scope versions consecutively' );
my %AfterMIMESuccess = $Ticket->TicketGet( TicketID => $TicketID, DynamicFields => 0, UserID => 1 );
isnt( $AfterMIMESuccess{UnlockTimeout}, 1, 'successful MIMEBase parent persists nested unlock-timeout value' );
my $ArticleEvents = $Audit->List(
    Subject => $Subject, TenantID => $Tenant, ObjectType => 'ticket_article', ObjectID => "$ArticleID",
);
is( [ map { $_->{Action} } @{ $ArticleEvents->{Data} } ], ['ticket.article.created'], 'article emits one normalized audit event' );
ok( !exists $ArticleEvents->{Data}->[0]->{Details}->{body}, 'article body is excluded from audit details' );
is( $Ticket->TicketUnlockTimeoutUpdate( TicketID => $TicketID, UnlockTimeout => 1, UserID => 1 ), 1, 'chat rollback fixture resets unlock timeout through audited direct path' );
my $ChatCreateVersion = $Kernel::OM->Get('Kernel::System::CareOnCloud::TicketAudit')->ScopeGet( TicketID => $TicketID )->{Version};
my $ChatBackend = $Kernel::OM->Get('Kernel::System::Ticket::Article')->BackendForChannel( ChannelName => 'Chat' );
ok( $ChatBackend, 'chat article backend resolves in the candidate runtime' );
my %ChatArticle = (
    TicketID => $TicketID, SenderType => 'agent', IsVisibleForCustomer => 1,
    ChatMessageList => [
        { ChatterID => 'audit-agent', ChatterName => 'Audit Agent', ChatterType => 'agent', MessageText => 'Audited chat message', SystemGenerated => 0, CreateTime => '2030-01-02 03:04:05' },
    ],
    HistoryType => 'AddNote', HistoryComment => 'CareOnCloud chat audit acceptance', UserID => 1,
);
$Helper->ConfigSettingChange( Key => 'CareOnCloud::Audit::Enabled', Value => 0 );
ok( !$ChatBackend->ArticleCreate(%ChatArticle), 'chat article create fails closed when audit is unavailable' );
is( scalar $Kernel::OM->Get('Kernel::System::Ticket::Article')->ArticleList( TicketID => $TicketID ), 1, 'failed audited chat create leaves no additional article row' );
my %AfterChatFailure = $Ticket->TicketGet( TicketID => $TicketID, DynamicFields => 0, UserID => 1 );
is( $AfterChatFailure{UnlockTimeout}, 1, 'failed Chat parent rolls nested unlock-timeout value back' );
is( $Kernel::OM->Get('Kernel::System::CareOnCloud::TicketAudit')->ScopeGet( TicketID => $TicketID )->{Version}, $ChatCreateVersion, 'failed chat article create rolls parent and nested scope versions back' );
$Helper->ConfigSettingChange( Key => 'CareOnCloud::Audit::Enabled', Value => 1 );
{
    no warnings 'redefine'; ## no critic
    local *Kernel::System::CareOnCloud::TicketAudit::_AuditRecord = sub {
        my ( $Self, %Param ) = @_;
        return { Success => 0, Error => 'INJECTED_TIMEOUT_AUDIT_FAILURE' }
            if ( $Param{Action} // q{} ) eq 'ticket.unlock_timeout.updated';
        return $OriginalAuditRecord->( $Self, %Param );
    };
    ok( !$ChatBackend->ArticleCreate(%ChatArticle), 'nested unlock-timeout audit failure rolls Chat parent back' );
}
is( scalar $Kernel::OM->Get('Kernel::System::Ticket::Article')->ArticleList( TicketID => $TicketID ), 1, 'nested timeout audit failure leaves no additional Chat article row' );
my %AfterInjectedChatFailure = $Ticket->TicketGet( TicketID => $TicketID, DynamicFields => 0, UserID => 1 );
is( $AfterInjectedChatFailure{UnlockTimeout}, 1, 'nested timeout audit failure restores Chat parent timeout' );
is( $Kernel::OM->Get('Kernel::System::CareOnCloud::TicketAudit')->ScopeGet( TicketID => $TicketID )->{Version}, $ChatCreateVersion, 'nested timeout audit failure restores Chat parent scope version' );
my $ChatArticleID = $ChatBackend->ArticleCreate(%ChatArticle);
ok( $ChatArticleID, 'chat article create succeeds after audit recovers' );
is( $Kernel::OM->Get('Kernel::System::CareOnCloud::TicketAudit')->ScopeGet( TicketID => $TicketID )->{Version}, $ChatCreateVersion + 2, 'successful Chat parent advances timeout and article scope versions consecutively' );
my %AfterChatSuccess = $Ticket->TicketGet( TicketID => $TicketID, DynamicFields => 0, UserID => 1 );
isnt( $AfterChatSuccess{UnlockTimeout}, 1, 'successful Chat parent persists nested unlock-timeout value' );
my $ChatEvents = $Audit->List(
    Subject => $Subject, TenantID => $Tenant, ObjectType => 'ticket_article', ObjectID => "$ChatArticleID",
);
is( [ map { $_->{Action} } @{ $ChatEvents->{Data} } ], ['ticket.chat_article.created'], 'chat article emits one normalized audit event' );
my @UpdatedChatMessages = (
    { ChatterID => 'audit-agent', ChatterName => 'Audit Agent', ChatterType => 'agent', MessageText => 'Updated audited chat message', SystemGenerated => 0, CreateTime => '2030-01-02 03:05:05' },
);
my $ChatVersion = $ChatCreateVersion + 2;
$Helper->ConfigSettingChange( Key => 'CareOnCloud::Audit::Enabled', Value => 0 );
ok( !$ChatBackend->ArticleUpdate( TicketID => $TicketID, ArticleID => $ChatArticleID, Key => 'ChatMessageList', Value => \@UpdatedChatMessages, UserID => 1 ), 'chat article update fails closed when audit is unavailable' );
is( $Kernel::OM->Get('Kernel::System::CareOnCloud::TicketAudit')->ScopeGet( TicketID => $TicketID )->{Version}, $ChatVersion, 'failed chat article update rolls scope version back' );
$Helper->ConfigSettingChange( Key => 'CareOnCloud::Audit::Enabled', Value => 1 );
ok( $ChatBackend->ArticleUpdate( TicketID => $TicketID, ArticleID => $ChatArticleID, Key => 'ChatMessageList', Value => \@UpdatedChatMessages, UserID => 1 ), 'chat article update succeeds after audit recovers' );
is( $Kernel::OM->Get('Kernel::System::CareOnCloud::TicketAudit')->ScopeGet( TicketID => $TicketID )->{Version}, $ChatVersion + 1, 'successful chat article update advances scope version once' );
$Helper->ConfigSettingChange( Key => 'CareOnCloud::Audit::Enabled', Value => 0 );
ok( !$ChatBackend->ArticleDelete( TicketID => $TicketID, ArticleID => $ChatArticleID, UserID => 1 ), 'chat article delete fails closed when audit is unavailable' );
is( $Kernel::OM->Get('Kernel::System::CareOnCloud::TicketAudit')->ScopeGet( TicketID => $TicketID )->{Version}, $ChatVersion + 1, 'failed chat article delete rolls scope version back' );
$Helper->ConfigSettingChange( Key => 'CareOnCloud::Audit::Enabled', Value => 1 );
ok( $ChatBackend->ArticleDelete( TicketID => $TicketID, ArticleID => $ChatArticleID, UserID => 1 ), 'chat article delete succeeds after audit recovers' );
is( $Kernel::OM->Get('Kernel::System::CareOnCloud::TicketAudit')->ScopeGet( TicketID => $TicketID )->{Version}, $ChatVersion + 2, 'successful chat article delete advances scope version once' );
$ChatEvents = $Audit->List( Subject => $Subject, TenantID => $Tenant, ObjectType => 'ticket_article', ObjectID => "$ChatArticleID" );
is( [ map { $_->{Action} } @{ $ChatEvents->{Data} } ], [qw(ticket.chat_article.created ticket.chat_article.updated ticket.chat_article.deleted)], 'chat article lifecycle emits normalized audit events' );
my %BeforeInvalidDelete = $Ticket->TicketGet( TicketID => $TicketID, DynamicFields => 0, UserID => 1 );
my $BeforeInvalidDeleteVersion = $Kernel::OM->Get('Kernel::System::CareOnCloud::TicketAudit')->ScopeGet( TicketID => $TicketID )->{Version};
my $InvalidArticleID = 900000000 + int rand 99999999;
my $InvalidDeleteOriginal = sub {
    my ( $Backend, %Param ) = @_;
    my @Values = ( 'Unknown-channel delete marker', $Param{TicketID} );
    my @Bind = map { \$_ } @Values;
    return $DB->Do( SQL => 'UPDATE ticket SET title = ? WHERE id = ?', Bind => \@Bind );
};
my $InvalidBackend = bless( {}, 'CareOnCloudTicketAuditInvalidBackendTest' );
$Helper->ConfigSettingChange( Key => 'CareOnCloud::Audit::Enabled', Value => 0 );
ok(
    !$Kernel::OM->Get('Kernel::System::CareOnCloud::TicketAudit')->InvalidArticleDeleteRun(
        ArticleBackend => $InvalidBackend, Original => $InvalidDeleteOriginal,
        Param => { TicketID => $TicketID, ArticleID => $InvalidArticleID, CommunicationChannelID => 999, UserID => 1 },
    ),
    'unknown-channel article delete fails closed when audit is unavailable',
);
my %AfterInvalidDeleteFailure = $Ticket->TicketGet( TicketID => $TicketID, DynamicFields => 0, UserID => 1 );
is( $AfterInvalidDeleteFailure{Title}, $BeforeInvalidDelete{Title}, 'failed unknown-channel delete rolls backend mutation back' );
is(
    $Kernel::OM->Get('Kernel::System::CareOnCloud::TicketAudit')->ScopeGet( TicketID => $TicketID )->{Version},
    $BeforeInvalidDeleteVersion,
    'failed unknown-channel delete rolls scope version back',
);
$Helper->ConfigSettingChange( Key => 'CareOnCloud::Audit::Enabled', Value => 1 );
ok(
    $Kernel::OM->Get('Kernel::System::CareOnCloud::TicketAudit')->InvalidArticleDeleteRun(
        ArticleBackend => $InvalidBackend, Original => $InvalidDeleteOriginal,
        Param => { TicketID => $TicketID, ArticleID => $InvalidArticleID, CommunicationChannelID => 999, UserID => 1 },
    ),
    'unknown-channel article delete succeeds after audit recovers',
);
is(
    $Kernel::OM->Get('Kernel::System::CareOnCloud::TicketAudit')->ScopeGet( TicketID => $TicketID )->{Version},
    $BeforeInvalidDeleteVersion + 1,
    'successful unknown-channel delete advances scope version once',
);
my $InvalidDeleteEvents = $Audit->List(
    Subject => $Subject, TenantID => $Tenant, ObjectType => 'ticket_article', ObjectID => "$InvalidArticleID",
);
is(
    [ map { $_->{Action} } @{ $InvalidDeleteEvents->{Data} } ],
    ['ticket.unknown_channel_article.deleted'],
    'unknown-channel delete emits one normalized audit event',
);
my %BeforeGIUpdate = $Ticket->TicketGet( TicketID => $TicketID, DynamicFields => 0, UserID => 1 );
my $BeforeGIUpdateVersion = $Kernel::OM->Get('Kernel::System::CareOnCloud::TicketAudit')->ScopeGet( TicketID => $TicketID )->{Version};
my $GIUpdateRollback = $Kernel::OM->Get('Kernel::System::CareOnCloud::TicketAudit')->GenericInterfaceTicketUpdateRun(
    Operation => bless( {}, 'CareOnCloudTicketAuditGIUpdateTest' ), Param => { Data => { TicketID => $TicketID } },
    Original => sub {
        my ( $Operation, %Param ) = @_;
        ok( $Ticket->TicketTitleUpdate( TicketID => $TicketID, Title => 'Generic Interface rollback title', UserID => 1 ), 'GI inner title mutation succeeds before request failure' );
        return { Success => 0, ErrorMessage => 'intentional GI request failure' };
    },
);
ok( !$GIUpdateRollback->{Success}, 'Generic Interface request failure is returned after rollback' );
my %AfterGIUpdate = $Ticket->TicketGet( TicketID => $TicketID, DynamicFields => 0, UserID => 1 );
is( $AfterGIUpdate{Title}, $BeforeGIUpdate{Title}, 'failed Generic Interface request rolls all ticket mutations back' );
is( $Kernel::OM->Get('Kernel::System::CareOnCloud::TicketAudit')->ScopeGet( TicketID => $TicketID )->{Version}, $BeforeGIUpdateVersion, 'failed Generic Interface request rolls scope mutations back' );
my $GICreateNumber = 'CareOnCloudGIC' . $Helper->GetRandomID();
my $GICreateRollback = $Kernel::OM->Get('Kernel::System::CareOnCloud::TicketAudit')->GenericInterfaceTicketCreateRun(
    Operation => bless( {}, 'CareOnCloudTicketAuditGICreateTest' ), Param => { Data => { Ticket => { Title => 'GI create rollback' } } },
    Original => sub {
        my ( $Operation, %Param ) = @_;
        my $CreatedTicketID = $Ticket->TicketCreate(
            TN => $GICreateNumber, Title => 'Generic Interface create rollback', QueueID => $QueueID,
            Lock => 'unlock', StateID => $StateID, PriorityID => $PriorityID,
            CustomerID => $Tenant, CustomerUser => 'gi-create-rollback-user', OwnerID => 1, UserID => 1,
        );
        ok( $CreatedTicketID, 'GI inner ticket creation succeeds before request failure' );
        return { Success => 0, ErrorMessage => 'intentional GI create request failure' };
    },
);
ok( !$GICreateRollback->{Success}, 'Generic Interface create request failure is returned after rollback' );
ok( !$Ticket->TicketIDLookup( TicketNumber => $GICreateNumber, UserID => 1 ), 'failed Generic Interface create leaves no ticket row' );
ok(
    !$Ticket->TicketCustomerSet( TicketID => $TicketID, No => $OtherTenant, User => 'other-user', UserID => 1 ),
    'ticket cannot be reassigned across tenant boundary',
);
my %AfterCrossTenant = $Ticket->TicketGet( TicketID => $TicketID, DynamicFields => 0, UserID => 1 );
is( $AfterCrossTenant{CustomerID}, $Tenant, 'cross-tenant customer mutation leaves tenant unchanged' );

my $UnscopedNumber = 'CareOnCloudUN' . $Helper->GetRandomID();
ok( !$Ticket->TicketCreate(
    TN => $UnscopedNumber, Title => 'Unscoped ticket', QueueID => $QueueID,
    Lock => 'unlock', StateID => $StateID, PriorityID => $PriorityID, OwnerID => 1, UserID => 1,
), 'ticket creation without an active tenant fails closed' );
ok( !$Ticket->TicketIDLookup( TicketNumber => $UnscopedNumber, UserID => 1 ), 'tenantless rejection leaves no ticket row' );

my $MergeMainID = $Ticket->TicketCreate(
    TN => 'CareOnCloudMM' . $Helper->GetRandomID(), Title => 'Merge target ticket', QueueID => $QueueID,
    Lock => 'unlock', StateID => $StateID, PriorityID => $PriorityID,
    CustomerID => $Tenant, CustomerUser => 'merge-main-user', OwnerID => 1, UserID => 1,
);
my $MergeSourceID = $Ticket->TicketCreate(
    TN => 'CareOnCloudMS' . $Helper->GetRandomID(), Title => 'Merge source ticket', QueueID => $QueueID,
    Lock => 'unlock', StateID => $StateID, PriorityID => $PriorityID,
    CustomerID => $Tenant, CustomerUser => 'merge-source-user', OwnerID => 1, UserID => 1,
);
my $CrossTenantMergeID = $Ticket->TicketCreate(
    TN => 'CareOnCloudMX' . $Helper->GetRandomID(), Title => 'Cross tenant merge source', QueueID => $QueueID,
    Lock => 'unlock', StateID => $StateID, PriorityID => $PriorityID,
    CustomerID => $OtherTenant, CustomerUser => 'cross-merge-user', OwnerID => 1, UserID => 1,
);
ok( $MergeMainID && $MergeSourceID && $CrossTenantMergeID, 'merge ticket fixtures are created with tenant scopes' );
ok( !$Ticket->TicketMerge( MainTicketID => $MergeMainID, MergeTicketID => $CrossTenantMergeID, UserID => 1 ), 'cross-tenant merge fails closed' );
my %CrossTenantMergeAfter = $Ticket->TicketGet( TicketID => $CrossTenantMergeID, DynamicFields => 0, UserID => 1 );
is( $CrossTenantMergeAfter{StateID}, $StateID, 'cross-tenant merge leaves source ticket unchanged' );
$Helper->ConfigSettingChange( Key => 'CareOnCloud::Audit::Enabled', Value => 0 );
ok( !$Ticket->TicketMerge( MainTicketID => $MergeMainID, MergeTicketID => $MergeSourceID, UserID => 1 ), 'same-tenant merge fails closed when audit is unavailable' );
my %MergeSourceAfterFailure = $Ticket->TicketGet( TicketID => $MergeSourceID, DynamicFields => 0, UserID => 1 );
is( $MergeSourceAfterFailure{StateID}, $StateID, 'failed audited merge rolls source ticket state back' );
is( $Kernel::OM->Get('Kernel::System::CareOnCloud::TicketAudit')->ScopeGet( TicketID => $MergeMainID )->{Version}, 1, 'failed merge rolls target scope version back' );
is( $Kernel::OM->Get('Kernel::System::CareOnCloud::TicketAudit')->ScopeGet( TicketID => $MergeSourceID )->{Version}, 1, 'failed merge rolls source scope version back' );
$Helper->ConfigSettingChange( Key => 'CareOnCloud::Audit::Enabled', Value => 1 );
ok( $Ticket->TicketMerge( MainTicketID => $MergeMainID, MergeTicketID => $MergeSourceID, UserID => 1 ), 'same-tenant merge succeeds after audit recovers' );
is( $Kernel::OM->Get('Kernel::System::CareOnCloud::TicketAudit')->ScopeGet( TicketID => $MergeMainID )->{Version}, 2, 'successful merge advances target scope version once' );
is( $Kernel::OM->Get('Kernel::System::CareOnCloud::TicketAudit')->ScopeGet( TicketID => $MergeSourceID )->{Version}, 2, 'successful merge advances source scope version once' );
my $MergeEvents = $Audit->List( Subject => $Subject, TenantID => $Tenant, ObjectType => 'ticket', ObjectID => "$MergeSourceID" );
is( [ map { $_->{Action} } @{ $MergeEvents->{Data} } ], [qw(ticket.created ticket.merged)], 'merge source receives one normalized merge event' );

$Events = $Audit->List( Subject => $Subject, TenantID => $Tenant, ObjectType => 'ticket', ObjectID => "$TicketID" );
is(
    [ map { $_->{Action} } @{ $Events->{Data} } ],
    $AlternateTypeID
        ? [qw(ticket.created ticket.state.updated ticket.type.updated ticket.service.updated ticket.sla.updated ticket.pending_time.updated ticket.title.updated ticket.customer.updated ticket.archive_flag.updated ticket.unlock_timeout.updated ticket.unlock_timeout.updated ticket.lock.updated ticket.unlock_timeout.updated ticket.unlock_timeout.updated ticket.unlock_timeout.updated ticket.unlock_timeout.updated)]
        : [qw(ticket.created ticket.state.updated ticket.service.updated ticket.sla.updated ticket.pending_time.updated ticket.title.updated ticket.customer.updated ticket.archive_flag.updated ticket.unlock_timeout.updated ticket.unlock_timeout.updated ticket.lock.updated ticket.unlock_timeout.updated ticket.unlock_timeout.updated ticket.unlock_timeout.updated ticket.unlock_timeout.updated)],
    'failed/no-op updates leave no orphan event and successful mutations emit one event each',
);
like( $Events->{Data}->[ $AlternateTypeID ? 7 : 6 ]->{ToState}, qr{\Asha256:[0-9a-f]{40}\z}, 'long customer state uses deterministic hash token' );
is(
    $Events->{Data}->[ $AlternateTypeID ? 7 : 6 ]->{Details}->{to_value}, "$Tenant|ticket-test-user-2",
    'full customer mutation value remains available in normalized details',
);
ok( $Audit->Verify( Subject => $Subject, TenantID => $Tenant )->{Valid}, 'ticket tenant audit chain verifies' );

my $BeforeDeleteVersion = $Kernel::OM->Get('Kernel::System::CareOnCloud::TicketAudit')->ScopeGet( TicketID => $TicketID )->{Version};
$Helper->ConfigSettingChange( Key => 'CareOnCloud::Audit::Enabled', Value => 0 );
ok( !$Ticket->TicketDelete( TicketID => $TicketID, UserID => 1 ), 'ticket delete fails closed when audit is unavailable' );
my %DeleteAfterFailure = $Ticket->TicketGet( TicketID => $TicketID, DynamicFields => 0, UserID => 1 );
ok( $DeleteAfterFailure{TicketID}, 'failed audited delete rolls the ticket row back' );
is( $Kernel::OM->Get('Kernel::System::CareOnCloud::TicketAudit')->ScopeGet( TicketID => $TicketID )->{Status}, 'active', 'failed audited delete keeps the scope active' );
$Helper->ConfigSettingChange( Key => 'CareOnCloud::Audit::Enabled', Value => 1 );
ok( $Ticket->TicketDelete( TicketID => $TicketID, UserID => 1 ), 'ticket delete succeeds after audit recovers' );
ok( !$Ticket->TicketGet( TicketID => $TicketID, DynamicFields => 0, UserID => 1 ), 'successful audited delete removes the ticket row' );
my $DeletedScope = $Kernel::OM->Get('Kernel::System::CareOnCloud::TicketAudit')->ScopeGet( TicketID => $TicketID );
is( $DeletedScope->{Status}, 'deleted', 'successful audited delete retains deleted scope tombstone' );
is( $DeletedScope->{Version}, $BeforeDeleteVersion + 1, 'successful audited delete advances scope version once' );
my $DeleteEvents = $Audit->List( Subject => $Subject, TenantID => $Tenant, ObjectType => 'ticket', ObjectID => "$TicketID" );
is( $DeleteEvents->{Data}->[-1]->{Action}, 'ticket.deleted', 'successful delete emits normalized audit evidence' );
ok( $Ticket->TicketDelete( TicketID => $LegacyTicketID, UserID => 1 ), 'legacy ticket fixture is removed' );
ok( $Ticket->TicketDelete( TicketID => $InvalidLegacyTicketID, UserID => 1 ), 'invalid legacy ticket fixture is removed' );
ok( $Ticket->TicketDelete( TicketID => $MergeMainID, UserID => 1 ), 'merge target fixture is removed' );
ok( $Ticket->TicketDelete( TicketID => $MergeSourceID, UserID => 1 ), 'merge source fixture is removed' );
ok( $Ticket->TicketDelete( TicketID => $CrossTenantMergeID, UserID => 1 ), 'cross-tenant merge fixture is removed' );
ok( $DB->Do( SQL => 'DELETE FROM careoncloud_ticket_scope WHERE ticket_id = ?', Bind => [ \$TicketID ] ), 'ticket scope fixture is removed' );
ok( $DB->Do( SQL => 'DELETE FROM careoncloud_ticket_scope WHERE ticket_id = ?', Bind => [ \$LegacyTicketID ] ), 'legacy ticket scope fixture is removed' );
ok( $DB->Do( SQL => 'DELETE FROM careoncloud_ticket_scope WHERE ticket_id = ?', Bind => [ \$InvalidLegacyTicketID ] ), 'explicit legacy ticket scope fixture is removed' );
ok( $DB->Do( SQL => 'DELETE FROM careoncloud_ticket_scope WHERE ticket_id = ?', Bind => [ \$MergeMainID ] ), 'merge target scope fixture is removed' );
ok( $DB->Do( SQL => 'DELETE FROM careoncloud_ticket_scope WHERE ticket_id = ?', Bind => [ \$MergeSourceID ] ), 'merge source scope fixture is removed' );
ok( $DB->Do( SQL => 'DELETE FROM careoncloud_ticket_scope WHERE ticket_id = ?', Bind => [ \$CrossTenantMergeID ] ), 'cross-tenant merge scope fixture is removed' );
ok( $DB->Do( SQL => 'DELETE FROM careoncloud_audit_event WHERE tenant_id = ?', Bind => [ \$Tenant ] ), 'ticket audit events are removed' );
ok( $DB->Do( SQL => 'DELETE FROM careoncloud_audit_head WHERE tenant_id = ?', Bind => [ \$Tenant ] ), 'ticket audit head is removed' );
ok( $DB->Do( SQL => 'DELETE FROM service_sla WHERE service_id = ? AND sla_id = ?', Bind => [ \$ServiceID, \$SLAID ] ), 'ticket audit service/SLA fixture link is removed' );
ok( $DB->Do( SQL => 'DELETE FROM sla WHERE id = ?', Bind => [ \$SLAID ] ), 'ticket audit SLA fixture is removed' );
ok( $DB->Do( SQL => 'DELETE FROM service WHERE id = ?', Bind => [ \$ServiceID ] ), 'ticket audit service fixture is removed' );
for my $TenantID ( $Tenant, $OtherTenant ) {
    ok( $DB->Do( SQL => 'DELETE FROM careoncloud_tenant WHERE key_name = ?', Bind => [ \$TenantID ] ), "tenant fixture $TenantID is removed" );
}
done_testing;
