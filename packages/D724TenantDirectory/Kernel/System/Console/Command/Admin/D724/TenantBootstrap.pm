# --
# D724 ESM is an enterprise service management platform based on OTOBO.
# Copyright (C) 2026 Data Market Bilgi Hizmetleri A.S.
# SPDX-License-Identifier: GPL-3.0-only
# --

package Kernel::System::Console::Command::Admin::D724::TenantBootstrap;

use v5.24;
use strict;
use warnings;
use parent qw(Kernel::System::Console::BaseCommand);

our @ObjectDependencies = ('Kernel::System::D724::TenantDirectory');

sub Configure {
    my ($Self) = @_;
    $Self->Description('Create the first D724 tenant and its initial tenant administrator.');
    $Self->AddOption( Name => 'tenant-id', Description => 'Stable tenant identifier.', Required => 1, HasValue => 1, ValueRegex => qr{[a-zA-Z0-9][a-zA-Z0-9._:-]{0,127}}smx );
    $Self->AddOption( Name => 'name', Description => 'Tenant display name.', Required => 1, HasValue => 1, ValueRegex => qr{.+}smx );
    $Self->AddOption( Name => 'admin-user-id', Description => 'Existing OTOBO agent user ID.', Required => 1, HasValue => 1, ValueRegex => qr{[1-9][0-9]*}smx );
    $Self->AddOption( Name => 'confirm-bootstrap', Description => 'Explicitly confirm the one-time bootstrap.', Required => 1, HasValue => 0 );
    return;
}

sub Run {
    my ($Self) = @_;
    my $Result = $Kernel::OM->Get('Kernel::System::D724::TenantDirectory')->Bootstrap(
        Confirm  => $Self->GetOption('confirm-bootstrap') ? 1 : 0,
        TenantID => $Self->GetOption('tenant-id'),
        Name     => $Self->GetOption('name'),
        UserID   => $Self->GetOption('admin-user-id'),
    );
    if (!$Result->{Success}) {
        $Self->PrintError( "Tenant bootstrap failed: $Result->{Error}" );
        return $Self->ExitCodeError();
    }
    $Self->Print("Tenant bootstrap completed.\n");
    return $Self->ExitCodeOk();
}

1;
