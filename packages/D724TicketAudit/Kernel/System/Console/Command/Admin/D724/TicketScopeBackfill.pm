# --
# Copyright (C) 2026 Data Market Bilgi Hizmetleri A.S.
# SPDX-License-Identifier: GPL-3.0-only
# --
package Kernel::System::Console::Command::Admin::D724::TicketScopeBackfill;

use v5.24;
use strict;
use warnings;
use parent qw(Kernel::System::Console::BaseCommand);

our $VERSION = '0.8.9';
our @ObjectDependencies = ('Kernel::System::D724::TicketAudit');

sub Configure {
    my ($Self) = @_;
    $Self->Description('Backfill immutable tenant scope and audit evidence for legacy OTOBO tickets with an active D724 customer tenant.');
    $Self->AddOption( Name => 'actor-user-id', Description => 'OTOBO user recorded as migration actor.', Required => 1, HasValue => 1, ValueRegex => qr{[1-9][0-9]*}smx );
    $Self->AddOption( Name => 'tenant-id', Description => 'Optional single tenant filter.', Required => 0, HasValue => 1, ValueRegex => qr{[a-z0-9][a-z0-9_-]{1,127}}smx );
    $Self->AddOption( Name => 'limit', Description => 'Maximum tickets in one atomic batch.', Required => 0, HasValue => 1, ValueRegex => qr{[1-9][0-9]*}smx );
    $Self->AddOption( Name => 'confirm', Description => 'Explicitly confirm the migration write.', Required => 1, HasValue => 0 );
    return;
}

sub Run {
    my ($Self) = @_;
    my $Result = $Kernel::OM->Get('Kernel::System::D724::TicketAudit')->Backfill(
        Confirm => $Self->GetOption('confirm') ? 1 : 0,
        UserID => $Self->GetOption('actor-user-id'),
        ( $Self->GetOption('tenant-id') ? ( TenantID => $Self->GetOption('tenant-id') ) : () ),
        ( $Self->GetOption('limit') ? ( Limit => $Self->GetOption('limit') ) : () ),
    );
    if (!$Result->{Success}) {
        $Self->PrintError("Ticket scope backfill failed: $Result->{Error}");
        return $Self->ExitCodeError();
    }
    $Self->Print("Ticket scope backfill completed: $Result->{Data}->{Backfilled}\n");
    return $Self->ExitCodeOk();
}

1;
