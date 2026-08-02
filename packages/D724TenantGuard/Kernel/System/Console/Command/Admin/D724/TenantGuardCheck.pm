# --
# CareOnCloud ESM enterprise service management platform.
# Copyright (C) 2026 Data Market Bilgi Hizmetleri A.S.
# SPDX-License-Identifier: GPL-3.0-only
# --

package Kernel::System::Console::Command::Admin::D724::TenantGuardCheck;

use v5.24;
use strict;
use warnings;

use parent qw(Kernel::System::Console::BaseCommand);

our @ObjectDependencies = (
    'Kernel::System::D724::TenantGuard',
    'Kernel::System::JSON',
);

sub Configure {
    my ( $Self, %Param ) = @_;

    $Self->Description('Evaluate a CareOnCloud tenant authorization decision.');
    $Self->AddOption(
        Name        => 'subject-id',
        Description => 'Trusted server-side subject identifier.',
        Required    => 1,
        HasValue    => 1,
        ValueRegex  => qr/.+/smx,
    );
    $Self->AddOption(
        Name        => 'subject-tenant',
        Description => 'Tenant assigned to the subject. Can be specified multiple times.',
        Required    => 1,
        HasValue    => 1,
        Multiple    => 1,
        ValueRegex  => qr/.+/smx,
    );
    $Self->AddOption(
        Name        => 'role',
        Description => 'Trusted server-side D724 role. Can be specified multiple times.',
        Required    => 1,
        HasValue    => 1,
        Multiple    => 1,
        ValueRegex  => qr/.+/smx,
    );
    $Self->AddOption(
        Name        => 'resource-tenant',
        Description => 'Tenant that owns the resource.',
        Required    => 1,
        HasValue    => 1,
        ValueRegex  => qr/.+/smx,
    );
    $Self->AddOption(
        Name        => 'action',
        Description => 'D724 action to authorize.',
        Required    => 1,
        HasValue    => 1,
        ValueRegex  => qr/.+/smx,
    );
    $Self->AddOption(
        Name        => 'json',
        Description => 'Print machine-readable JSON output.',
        Required    => 0,
        HasValue    => 0,
    );

    return;
}

sub Run {
    my ( $Self, %Param ) = @_;

    my $Decision = $Kernel::OM->Get('Kernel::System::D724::TenantGuard')->DecisionGet(
        Subject => {
            ID        => $Self->GetOption('subject-id'),
            TenantIDs => $Self->GetOption('subject-tenant'),
            Roles     => $Self->GetOption('role'),
        },
        Resource => {
            TenantID => $Self->GetOption('resource-tenant'),
        },
        Action => $Self->GetOption('action'),
    );

    if ( $Self->GetOption('json') ) {
        $Self->Print(
            $Kernel::OM->Get('Kernel::System::JSON')->Encode(
                Data     => $Decision,
                SortKeys => 1,
                Pretty   => 1,
            )
        );
    }
    else {
        $Self->Print("Allowed: $Decision->{Allowed}\n");
        $Self->Print("Reason: $Decision->{Reason}\n");
        $Self->Print("Policy: $Decision->{PolicyVersion}\n");
    }

    return $Decision->{Allowed} ? $Self->ExitCodeOk() : $Self->ExitCodeError();
}

1;
