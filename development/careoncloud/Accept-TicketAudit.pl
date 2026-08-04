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
my $TenantID = $ARGV[0] // 'careoncloud-demo';
my $UserID   = $ARGV[1] // 1;
my $TN       = 'CareOnCloudAUD20260724001';
die "tenant invalid\n" if $TenantID !~ m{\A[a-z0-9][a-z0-9_-]{1,127}\z}smx;
die "user id invalid\n" if $UserID !~ m{\A[1-9][0-9]*\z}smx;

my $Ticket = $Kernel::OM->Get('Kernel::System::Ticket');
my $TicketID = $Ticket->TicketIDLookup( TicketNumber => $TN, UserID => $UserID );
my $Created = 0;
if (!$TicketID) {
    $TicketID = $Ticket->TicketCreate(
        TN => $TN, Title => 'CareOnCloud atomic ticket and article audit acceptance',
        Queue => 'Raw', Lock => 'unlock', State => 'new', Priority => '3 normal',
        CustomerID => $TenantID, CustomerUser => 'demo.customer', OwnerID => $UserID, UserID => $UserID,
    );
    die "ticket create failed\n" if !$TicketID;
    die "ticket state update failed\n" if !$Ticket->TicketStateSet(
        TicketID => $TicketID, State => 'open', UserID => $UserID,
    );
    my $ArticleID = $Kernel::OM->Get('Kernel::System::Ticket::Article')->BackendForChannel( ChannelName => 'Internal' )->ArticleCreate(
        TicketID => $TicketID, SenderType => 'agent', IsVisibleForCustomer => 1,
        From => 'CareOnCloud Demo Agent <demo.agent@example.com>', To => 'CareOnCloud Demo Customer <demo.customer@example.com>',
        Subject => 'Atomic article audit accepted', Body => 'This visible demo article proves the audited MIME article flow.',
        ContentType => 'text/plain; charset=utf-8', HistoryType => 'AddNote', HistoryComment => 'CareOnCloud ticket audit acceptance',
        UserID => $UserID, NoAgentNotify => 1,
    );
    die "article create failed\n" if !$ArticleID;
    $Created = 1;
}

my $Scope = $Kernel::OM->Get('Kernel::System::CareOnCloud::TicketAudit')->ScopeGet( TicketID => $TicketID );
die "ticket scope missing\n" if !$Scope;
my $Subject = { ID => 'ticket-acceptance', TenantIDs => [$TenantID], RoleBindings => { $TenantID => ['tenant_admin'] } };
my $Events = $Kernel::OM->Get('Kernel::System::CareOnCloud::Audit')->List(
    Subject => $Subject, TenantID => $TenantID, AfterSequence => 0, Limit => 1000,
);
die "audit list failed: $Events->{Error}\n" if !$Events->{Success};
my @TicketEvents = grep { ( $_->{CorrelationID} // q{} ) eq "ticket:$TicketID" } @{ $Events->{Data} };
my $Verify = $Kernel::OM->Get('Kernel::System::CareOnCloud::Audit')->Verify( Subject => $Subject, TenantID => $TenantID );
die "audit verify failed\n" if !$Verify->{Success} || !$Verify->{Valid};
my %TicketData = $Ticket->TicketGet( TicketID => $TicketID, DynamicFields => 0, UserID => $UserID );
say $Kernel::OM->Get('Kernel::System::JSON')->Encode(
    Data => {
        Success => 1, Created => $Created, TenantID => $TenantID, TicketID => $TicketID,
        TicketNumber => $TicketData{TicketNumber}, State => $TicketData{State}, ScopeVersion => $Scope->{Version},
        Actions => [ map { $_->{Action} } @TicketEvents ], AuditChainValid => 1,
    }, SortKeys => 1, Pretty => 1,
);
