# --
# Copyright (C) 2026 Data Market Bilgi Hizmetleri A.S.
# SPDX-License-Identifier: GPL-3.0-only
# --
package Kernel::System::Console::Command::Admin::D724::TicketScopeAssign;

use v5.24;
use strict;
use warnings;
use parent qw(Kernel::System::Console::BaseCommand);

our $VERSION = '0.8.4';
our @ObjectDependencies = ('Kernel::System::D724::TicketAudit');

sub Configure {
    my ($Self) = @_;
    $Self->Description('Explicitly assign one legacy OTOBO ticket to an active D724 tenant with atomic audit evidence.');
    $Self->AddOption( Name => 'ticket-id', Description => 'Legacy OTOBO ticket ID.', Required => 1, HasValue => 1, ValueRegex => qr{[1-9][0-9]*}smx );
    $Self->AddOption( Name => 'tenant-id', Description => 'Active D724 tenant identifier.', Required => 1, HasValue => 1, ValueRegex => qr{[a-z0-9][a-z0-9_-]{1,127}}smx );
    $Self->AddOption( Name => 'actor-user-id', Description => 'OTOBO user recorded as migration actor.', Required => 1, HasValue => 1, ValueRegex => qr{[1-9][0-9]*}smx );
    $Self->AddOption( Name => 'replace-customer-id', Description => 'Explicitly replace a mismatching legacy CustomerID with the tenant ID.', Required => 0, HasValue => 0 );
    $Self->AddOption( Name => 'confirm', Description => 'Explicitly confirm this migration write.', Required => 1, HasValue => 0 );
    return;
}

sub Run {
    my ($Self) = @_;
    my $Result = $Kernel::OM->Get('Kernel::System::D724::TicketAudit')->AssignLegacy(
        Confirm => $Self->GetOption('confirm') ? 1 : 0,
        TicketID => $Self->GetOption('ticket-id'), TenantID => $Self->GetOption('tenant-id'),
        UserID => $Self->GetOption('actor-user-id'), ReplaceCustomerID => $Self->GetOption('replace-customer-id') ? 1 : 0,
    );
    if (!$Result->{Success}) {
        $Self->PrintError("Ticket scope assignment failed: $Result->{Error}");
        return $Self->ExitCodeError();
    }
    $Self->Print("Ticket scope assigned: $Result->{Data}->{TicketID} -> $Result->{Data}->{TenantID}\n");
    return $Self->ExitCodeOk();
}

1;
