#!/usr/bin/env perl
# --
# Copyright (C) 2026 Data Market Bilgi Hizmetleri A.S.
# SPDX-License-Identifier: GPL-3.0-only
# --
use v5.24;
use strict;
use warnings;
use Kernel::System::ObjectManager;

local $Kernel::OM = Kernel::System::ObjectManager->new();
my $UserID = 2; # quick_setup.pl's explicitly-created admin user
my $Suffix = time() . q{-} . int rand 10_000;
my $TenantA = "generic-agent-a-$Suffix";
my $TenantB = "generic-agent-b-$Suffix";
my $Directory = $Kernel::OM->Get('Kernel::System::D724::TenantDirectory');
for my $TenantID ( $TenantA, $TenantB ) {
    my $Bootstrap = $Directory->Bootstrap(
        Confirm => 1, TenantID => $TenantID, Name => "GenericAgent acceptance $TenantID", UserID => $UserID,
    );
    die "tenant bootstrap failed for $TenantID\n" if !$Bootstrap->{Success};
}

my $Ticket = $Kernel::OM->Get('Kernel::System::Ticket');
my $Title = "GenericAgent tenant acceptance $Suffix";
my %TicketID;
for my $TenantID ( $TenantA, $TenantB ) {
    $TicketID{$TenantID} = $Ticket->TicketCreate(
        TN => 'D724GA' . $Suffix . ( $TenantID eq $TenantA ? 'A' : 'B' ),
        Title => $Title, Queue => 'Raw', Lock => 'unlock', State => 'new', Priority => '3 normal',
        CustomerID => $TenantID, CustomerUser => "generic.agent.$TenantID", OwnerID => $UserID, UserID => $UserID,
    );
    die "ticket create failed for $TenantID\n" if !$TicketID{$TenantID};
}

my $GenericAgent = $Kernel::OM->Get('Kernel::System::GenericAgent');
my $Ran = $GenericAgent->JobRun(
    Job => "D724GenericAgentTenantScope-$Suffix", UserID => 1,
    Config => {
        CustomerID => $TenantA,
        New => { Priority => '4 high' },
    },
);
die "GenericAgent job did not complete\n" if !$Ran;

for my $TenantID ( $TenantA, $TenantB ) {
    $Ticket->_TicketCacheClear( TicketID => $TicketID{$TenantID} );
}
my %UpdatedA = $Ticket->TicketGet( TicketID => $TicketID{$TenantA}, DynamicFields => 0, UserID => $UserID );
my %UpdatedB = $Ticket->TicketGet( TicketID => $TicketID{$TenantB}, DynamicFields => 0, UserID => $UserID );
die "GenericAgent did not update scoped tenant ticket\n" if $UpdatedA{Priority} ne '4 high';
die "GenericAgent crossed tenant scope\n" if $UpdatedB{Priority} ne '3 normal';

my $Audit = $Kernel::OM->Get('Kernel::System::D724::Audit');
my $SubjectA = { ID => 'generic-agent-acceptance', TenantIDs => [$TenantA], RoleBindings => { $TenantA => ['tenant_admin'] } };
my $EventsA = $Audit->List(
    Subject => $SubjectA, TenantID => $TenantA, ObjectType => 'ticket', ObjectID => "$TicketID{$TenantA}", Limit => 100,
);
die "GenericAgent tenant audit list failed\n" if !$EventsA->{Success};
die "GenericAgent priority audit event missing\n" if !grep { $_->{Action} eq 'ticket.priority.updated' } @{ $EventsA->{Data} };
my $VerifyA = $Audit->Verify( Subject => $SubjectA, TenantID => $TenantA );
die "GenericAgent tenant audit chain verification failed\n" if !$VerifyA->{Success} || !$VerifyA->{Valid};

say $Kernel::OM->Get('Kernel::System::JSON')->Encode(
    Data => { Success => 1, scoped_ticket_id => 0 + $TicketID{$TenantA}, excluded_ticket_id => 0 + $TicketID{$TenantB} },
    SortKeys => 1, Pretty => 1,
);
