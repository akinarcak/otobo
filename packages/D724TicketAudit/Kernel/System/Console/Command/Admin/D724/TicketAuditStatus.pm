# --
# Copyright (C) 2026 Data Market Bilgi Hizmetleri A.S.
# SPDX-License-Identifier: GPL-3.0-only
# --
package Kernel::System::Console::Command::Admin::D724::TicketAuditStatus;

use v5.24;
use strict;
use warnings;
use parent qw(Kernel::System::Console::BaseCommand);

our $VERSION = '0.8.18';
our @ObjectDependencies = ( 'Kernel::Config', 'Kernel::System::DB', 'Kernel::System::JSON' );

sub Configure {
    my ($Self) = @_;
    $Self->Description('Report D724 OTOBO ticket tenant-binding and audit adapter health.');
    $Self->AddOption( Name => 'json', Description => 'Print JSON.', Required => 0, HasValue => 0 );
    return;
}

sub Run {
    my ($Self) = @_;
    my $DB = $Kernel::OM->Get('Kernel::System::DB');
    my %Existing = map { $_ => 1 } $DB->ListTables();
    my $Table = $Existing{d724_ticket_scope} ? 1 : 0;
    my ( $Tickets, $Tenants, $CoreTickets, $Unbound, $Backfillable ) = ( 0, 0, 0, 0, 0 );
    my @UnboundList;
    if ($Table) {
        $DB->Prepare( SQL => 'SELECT COUNT(*), COUNT(DISTINCT tenant_id) FROM d724_ticket_scope' );
        ( $Tickets, $Tenants ) = $DB->FetchrowArray();
        $DB->Prepare( SQL => 'SELECT COUNT(*) FROM ticket' );
        ($CoreTickets) = $DB->FetchrowArray();
        $DB->Prepare( SQL => 'SELECT COUNT(*) FROM ticket t LEFT JOIN d724_ticket_scope s ON s.ticket_id = t.id WHERE s.ticket_id IS NULL' );
        ($Unbound) = $DB->FetchrowArray();
        $DB->Prepare(
            SQL => "SELECT COUNT(*) FROM ticket t JOIN d724_tenant d ON d.key_name = t.customer_id AND d.status = 'active' LEFT JOIN d724_ticket_scope s ON s.ticket_id = t.id WHERE s.ticket_id IS NULL",
        );
        ($Backfillable) = $DB->FetchrowArray();
        $DB->Prepare(
            SQL => 'SELECT t.id, t.tn, t.customer_id FROM ticket t LEFT JOIN d724_ticket_scope s ON s.ticket_id = t.id WHERE s.ticket_id IS NULL ORDER BY t.id', Limit => 100,
        );
        while ( my @Row = $DB->FetchrowArray() ) {
            push @UnboundList, { TicketID => $Row[0], TicketNumber => $Row[1], CustomerID => $Row[2] // q{} };
        }
    }
    my $Config = $Kernel::OM->Get('Kernel::Config');
    my $SearchEnabled = $Config->Get('D724::SearchPolicy::Enabled') ? 1 : 0;
    my $SafeIndexes = $Config->Get('D724::SearchPolicy::TenantSafeIndexes') // [];
    my $SafeIndexConfigValid = ref $SafeIndexes eq 'ARRAY' && @{$SafeIndexes} == 1 && $SafeIndexes->[0] eq 'ticket' ? 1 : 0;
    my $Status = {
        Success => $Table && !$Unbound && $SearchEnabled && $SafeIndexConfigValid ? 1 : 0,
        Package => 'D724TicketAudit', Version => $VERSION,
        Enabled => $Kernel::OM->Get('Kernel::Config')->Get('D724::TicketAudit::Enabled') ? 1 : 0,
        Tables => { d724_ticket_scope => $Table }, Counts => {
            Tickets => $Tickets, Tenants => $Tenants, CoreTickets => $CoreTickets,
            UnboundTickets => $Unbound, BackfillableTickets => $Backfillable,
            InvalidTenantTickets => $Unbound - $Backfillable,
        },
        Unbound => \@UnboundList,
        SearchPolicy => {
            Enabled => $SearchEnabled, ContractVersion => 1,
            TenantSafeIndexes => $SafeIndexes, ConfigValid => $SafeIndexConfigValid,
            TenantField => 'CustomerID', DirectUnscopedRequest => 'deny',
        },
    };
    if ( $Self->GetOption('json') ) {
        $Self->Print( $Kernel::OM->Get('Kernel::System::JSON')->Encode( Data => $Status, Pretty => 1, SortKeys => 1 ) . "\n" );
    }
    else { $Self->Print("D724TicketAudit $VERSION: " . ( $Status->{Success} ? 'OK' : 'FAILED' ) . "\n") }
    return $Status->{Success} ? $Self->ExitCodeOk() : $Self->ExitCodeError();
}

1;
