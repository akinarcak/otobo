# --
# Copyright (C) 2026 Data Market Bilgi Hizmetleri A.S.
# SPDX-License-Identifier: GPL-3.0-only
# --
package Kernel::System::Console::Command::Admin::D724::APIClientRotate;

use v5.24;
use strict;
use warnings;
use parent qw(Kernel::System::Console::BaseCommand);

our $VERSION = '0.5.0';
our @ObjectDependencies = (
    'Kernel::System::D724::APIAuth',
    'Kernel::System::D724::TenantDirectory',
);

sub Configure {
    my ($Self) = @_;
    $Self->Description('Atomically rotate a tenant-bound API client secret and revoke its active tokens.');
    for my $Option (
        [ 'tenant-id', 'Tenant key.' ],
        [ 'client-id', 'API client ID.' ],
        [ 'expected-version', 'Current optimistic client version.' ],
        [ 'actor-user-id', 'Tenant administrator user ID.' ],
    ) {
        $Self->AddOption(
            Name => $Option->[0], Description => $Option->[1],
            Required => 1, HasValue => 1,
        );
    }
    $Self->AddOption(
        Name => 'confirm', Description => 'Confirm rotation and active-token revocation.',
        Required => 1, HasValue => 0,
    );
    return;
}

sub Run {
    my ($Self) = @_;
    return $Self->ExitCodeError() if !$Self->GetOption('confirm');
    my $UserID = $Self->GetOption('actor-user-id');
    my $Context = $Kernel::OM->Get('Kernel::System::D724::TenantDirectory')->ContextGet(
        UserID => $UserID,
    );
    if ( !$Context->{Success} ) {
        $Self->PrintError("Actor context failed: $Context->{Error}");
        return $Self->ExitCodeError();
    }
    my $Result = $Kernel::OM->Get('Kernel::System::D724::APIAuth')->ClientSecretRotate(
        Subject         => $Context->{Subject},
        TenantID        => $Self->GetOption('tenant-id'),
        ClientID        => $Self->GetOption('client-id'),
        ExpectedVersion => $Self->GetOption('expected-version'),
        UserID          => $UserID,
    );
    if ( !$Result->{Success} ) {
        $Self->PrintError("API client rotation failed: $Result->{Error}");
        return $Self->ExitCodeError();
    }
    $Self->Print(
        "ClientID=$Result->{Data}->{ClientID}\n"
            . "ClientVersion=$Result->{Data}->{Version}\n"
            . "ClientSecret=$Result->{Data}->{ClientSecret}\n"
            . "Store this secret now; the old secret and all old tokens are invalid.\n",
    );
    return $Self->ExitCodeOk();
}

1;
