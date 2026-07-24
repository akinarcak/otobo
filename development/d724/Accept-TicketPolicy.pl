#!/usr/bin/env perl
# --
# Copyright (C) 2026 Data Market Bilgi Hizmetleri A.S.
# SPDX-License-Identifier: GPL-3.0-only
# --
use v5.24;
use strict;
use warnings;
use Kernel::System::ObjectManager;
use Kernel::GenericInterface::Operation::Ticket::Common ();

local $Kernel::OM = Kernel::System::ObjectManager->new();
my $AgentLogin = $ARGV[0] // 'demo.agent';
my $TenantID   = $ARGV[1] // 'd724-demo';
my $TN         = $ARGV[2] // 'D724AUD20260724001';
die "tenant invalid\n" if $TenantID !~ m{\A[a-z0-9][a-z0-9_-]{1,127}\z}smx;

my $UserID = $Kernel::OM->Get('Kernel::System::User')->UserLookup( UserLogin => $AgentLogin );
die "agent not found\n" if !$UserID;
my $Ticket = $Kernel::OM->Get('Kernel::System::Ticket');
my $TicketID = $Ticket->TicketIDLookup( TicketNumber => $TN, UserID => $UserID );
die "acceptance ticket not found\n" if !$TicketID;

my @Visible = $Ticket->TicketSearch(
    UserID => $UserID, Result => 'ARRAY', TicketNumber => $TN, Limit => 10,
);
die "scoped ticket search failed\n" if @Visible != 1 || $Visible[0] != $TicketID;

my $Policy = $Kernel::OM->Get('Kernel::System::D724::TicketPolicy');
my $Access = $Policy->TicketAccessCheck( UserID => $UserID, TicketID => $TicketID );
die "ticket policy access failed\n" if !$Access->{Success} || $Access->{TenantID} ne $TenantID;
my $RawBypass = $Policy->SearchScopeApply(
    Param => { UserID => $UserID, CustomerIDRaw => $TenantID },
);
die "raw search bypass was not denied\n"
    if $RawBypass->{Success} || $RawBypass->{Reason} ne 'CUSTOMER_ID_RAW_FORBIDDEN';

my $GICommon = bless {}, 'Kernel::GenericInterface::Operation::Ticket::Common';
die "Generic Interface tenant access failed\n" if !$GICommon->CheckAccessPermissions(
    UserID => $UserID, UserType => 'User', TicketID => $TicketID,
);

say $Kernel::OM->Get('Kernel::System::JSON')->Encode(
    Data => {
        Success => 1, AgentLogin => $AgentLogin, UserID => $UserID,
        TenantID => $TenantID, TicketID => $TicketID, TicketNumber => $TN,
        SearchVisibleIDs => \@Visible, RawBypassDenied => 1, GenericInterfaceAccess => 1,
    },
    SortKeys => 1, Pretty => 1,
);
