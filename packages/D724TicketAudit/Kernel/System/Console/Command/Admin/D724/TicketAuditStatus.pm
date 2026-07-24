# --
# Copyright (C) 2026 Data Market Bilgi Hizmetleri A.S.
# SPDX-License-Identifier: GPL-3.0-only
# --
package Kernel::System::Console::Command::Admin::D724::TicketAuditStatus;

use v5.24;
use strict;
use warnings;
use parent qw(Kernel::System::Console::BaseCommand);

our $VERSION = '0.1.1';
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
    my ( $Tickets, $Tenants ) = ( 0, 0 );
    if ($Table) {
        $DB->Prepare( SQL => 'SELECT COUNT(*), COUNT(DISTINCT tenant_id) FROM d724_ticket_scope' );
        ( $Tickets, $Tenants ) = $DB->FetchrowArray();
    }
    my $Status = {
        Success => $Table ? 1 : 0, Package => 'D724TicketAudit', Version => '0.1.1',
        Enabled => $Kernel::OM->Get('Kernel::Config')->Get('D724::TicketAudit::Enabled') ? 1 : 0,
        Tables => { d724_ticket_scope => $Table }, Counts => { Tickets => $Tickets, Tenants => $Tenants },
    };
    if ( $Self->GetOption('json') ) {
        $Self->Print( $Kernel::OM->Get('Kernel::System::JSON')->Encode( Data => $Status, Pretty => 1, SortKeys => 1 ) . "\n" );
    }
    else { $Self->Print("D724TicketAudit 0.1.1: " . ( $Status->{Success} ? 'OK' : 'FAILED' ) . "\n") }
    return $Status->{Success} ? $Self->ExitCodeOk() : $Self->ExitCodeError();
}

1;
