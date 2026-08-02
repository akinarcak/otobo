#!/usr/bin/env perl
# --
# Copyright (C) 2026 Data Market Bilgi Hizmetleri A.S.
# SPDX-License-Identifier: GPL-3.0-only
# --
use v5.24;
use strict;
use warnings;
use Time::HiRes qw(sleep);
use Kernel::System::ObjectManager;

local $Kernel::OM = Kernel::System::ObjectManager->new();
if ( ( $ARGV[0] // q{} ) eq '--verify' ) {
    my $TicketID = $ARGV[1];
    my $ExpectedState = $ARGV[2];
    die "scheduler verifier ticket id invalid\n" if !defined $TicketID || $TicketID !~ m{\A[1-9][0-9]*\z};
    die "scheduler verifier expected state missing\n" if !defined $ExpectedState || !length $ExpectedState;
    my $UserID = 2;
    my $Ticket = $Kernel::OM->Get('Kernel::System::Ticket');
    my %Updated = $Ticket->TicketGet( TicketID => $TicketID, DynamicFields => 0, UserID => $UserID );
    die "scheduler verifier ticket missing\n" if !%Updated;
    die "scheduler did not apply pending target state\n" if $Updated{State} ne $ExpectedState;
    my $DB = $Kernel::OM->Get('Kernel::System::DB');
    die "scheduler verifier scope query failed\n" if !$DB->Prepare(
        SQL => 'SELECT tenant_id, version, status FROM d724_ticket_scope WHERE ticket_id = ?', Bind => [ \$TicketID ], Limit => 1,
    );
    my @RawScope = $DB->FetchrowArray();
    my $Scope = $Kernel::OM->Get('Kernel::System::D724::TicketAudit')->ScopeGet( TicketID => $TicketID );
    die "scheduler ticket scope missing after state=$Updated{State} raw_scope="
        . ( defined $RawScope[0] ? join( q{|}, @RawScope ) : 'none' ) . "\n" if !$Scope || $Scope->{Version} < 4;
    my $TenantID = $Scope->{TenantID};
    my $Subject = { ID => 'scheduler-acceptance', TenantIDs => [$TenantID], RoleBindings => { $TenantID => ['tenant_admin'] } };
    my $Events = $Kernel::OM->Get('Kernel::System::D724::Audit')->List(
        Subject => $Subject, TenantID => $TenantID, ObjectType => 'ticket', ObjectID => "$TicketID", Limit => 100,
    );
    die "scheduler audit list failed\n" if !$Events->{Success};
    my %Action = map { $_->{Action} => 1 } @{ $Events->{Data} };
    die "scheduler state audit event missing\n" if !$Action{'ticket.state.updated'};
    my $Verify = $Kernel::OM->Get('Kernel::System::D724::Audit')->Verify( Subject => $Subject, TenantID => $TenantID );
    die "scheduler audit chain verification failed\n" if !$Verify->{Success} || !$Verify->{Valid};
    say $Kernel::OM->Get('Kernel::System::JSON')->Encode(
        Data => { Success => 1, TicketID => 0 + $TicketID, State => $Updated{State}, ScopeVersion => 0 + $Scope->{Version} },
        SortKeys => 1, Pretty => 1,
    );
    exit 0;
}

my $UserID   = 2; # quick_setup.pl's explicitly-created admin user
my $TenantID = 'gi-acceptance'; # created by the preceding HTTP acceptance
my $Ticket   = $Kernel::OM->Get('Kernel::System::Ticket');
my $Config   = $Kernel::OM->Get('Kernel::Config');
my %AfterPending = %{ $Config->Get('Ticket::StateAfterPending') // {} };
my ($PendingState) = sort keys %AfterPending;
die "no Ticket::StateAfterPending mapping\n" if !$PendingState || !$AfterPending{$PendingState};

my $TicketID = $Ticket->TicketCreate(
    TN => 'D724SCH' . time(), Title => 'Scheduler pending-check acceptance',
    Queue => 'Raw', Lock => 'unlock', State => 'new', Priority => '3 normal',
    CustomerID => $TenantID, CustomerUser => 'scheduler.acceptance', OwnerID => $UserID, UserID => $UserID,
);
die "ticket create failed\n" if !$TicketID;
my $Past = $Kernel::OM->Create('Kernel::System::DateTime');
$Past->Subtract( Minutes => 5 );
die "pending time setup failed\n" if !$Ticket->TicketPendingTimeSet(
    TicketID => $TicketID, String => $Past->ToString(), UserID => $UserID,
);
die "pending state setup failed\n" if !$Ticket->TicketStateSet(
    TicketID => $TicketID, State => $PendingState, UserID => $UserID,
);
my $Before = $Kernel::OM->Get('Kernel::System::D724::TicketAudit')->ScopeGet( TicketID => $TicketID );
die "scheduler ticket scope missing before task execution\n" if !$Before || $Before->{Version} < 3;

my $SchedulerDB = $Kernel::OM->Get('Kernel::System::Daemon::SchedulerDB');
my $TaskID = $SchedulerDB->TaskAdd(
    Type => 'Cron', Name => 'D724SchedulerPendingCheckAcceptance', Attempts => 1,
    MaximumParallelInstances => 1,
    Data => {
        Module => 'Kernel::System::Console::Command::Maint::Ticket::PendingCheck',
        Function => 'Execute', Params => [],
    },
);
die "scheduler task create failed\n" if !$TaskID || $TaskID < 0;

my $Worker = $Kernel::OM->Get('Kernel::System::Daemon::DaemonModules::SchedulerTaskWorker');
local $SIG{CHLD} = 'IGNORE';
my $Completed;
for ( 1 .. 80 ) {
    $Worker->Run();
    $Worker->_WorkerPIDsCheck();
    my @Tasks = $SchedulerDB->TaskList();
    if ( !grep { $_->{TaskID} == $TaskID } @Tasks ) { $Completed = 1; last }
    sleep 0.25;
}
die "scheduler task did not complete\n" if !$Completed;

local $SIG{CHLD} = 'DEFAULT';
my $VerifyExit = system $^X, '-I.', '-IKernel/cpan-lib', '-ICustom', $0, '--verify', $TicketID, $AfterPending{$PendingState};
die "scheduler verifier failed\n" if $VerifyExit != 0;
