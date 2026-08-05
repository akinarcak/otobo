# --
# Copyright (C) 2026 Data Market Bilgi Hizmetleri A.S.
# SPDX-License-Identifier: GPL-3.0-only
# --
package Kernel::System::Console::Command::Admin::CareOnCloud::TicketScopeAssign;

use v5.24;
use strict;
use warnings;
use parent qw(Kernel::System::Console::BaseCommand);

our $VERSION = '0.8.12';
our @ObjectDependencies = ('Kernel::System::CareOnCloud::TicketAudit');

sub Configure {
    my ($Self) = @_;
    $Self->Description('Explicitly assign one legacy CareOnCloud ESM ticket to an active CareOnCloud tenant with atomic audit evidence.');
    $Self->AddOption( Name => 'ticket-id', Description => 'Legacy CareOnCloud ESM ticket ID.', Required => 1, HasValue => 1, ValueRegex => qr{[1-9][0-9]*}smx );
    $Self->AddOption( Name => 'tenant-id', Description => 'Active CareOnCloud tenant identifier.', Required => 1, HasValue => 1, ValueRegex => qr{[a-z0-9][a-z0-9_-]{1,127}}smx );
    $Self->AddOption( Name => 'actor-user-id', Description => 'CareOnCloud ESM user recorded as migration actor.', Required => 1, HasValue => 1, ValueRegex => qr{[1-9][0-9]*}smx );
    $Self->AddOption( Name => 'replace-customer-id', Description => 'Explicitly replace a mismatching legacy CustomerID with the tenant ID.', Required => 0, HasValue => 0 );
    $Self->AddOption( Name => 'confirm', Description => 'Explicitly confirm this migration write.', Required => 1, HasValue => 0 );
    return;
}

sub Run {
    my ($Self) = @_;
    my $Result = $Kernel::OM->Get('Kernel::System::CareOnCloud::TicketAudit')->AssignLegacy(
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
