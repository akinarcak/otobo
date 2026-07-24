# --
# D724 ESM is an enterprise service management platform based on OTOBO.
# Copyright (C) 2026 Data Market Bilgi Hizmetleri A.S.
# SPDX-License-Identifier: GPL-3.0-only
# --
package Kernel::System::Console::Command::Admin::D724::CommitmentReplay;

use v5.24;
use strict;
use warnings;
use parent qw(Kernel::System::Console::BaseCommand);

our $VERSION = '0.4.1';
our @ObjectDependencies = (
    'Kernel::System::D724::EscalationDispatcher',
    'Kernel::System::D724::TenantDirectory',
);

sub Configure {
    my ($Self) = @_;
    $Self->Description('Replay one tenant-scoped dead-letter commitment escalation.');
    $Self->AddOption( Name => 'tenant-id', Description => 'Tenant identifier.', Required => 1, HasValue => 1 );
    $Self->AddOption( Name => 'outbox-id', Description => 'Dead-letter outbox identifier.', Required => 1, HasValue => 1 );
    $Self->AddOption( Name => 'expected-attempt-count', Description => 'Current attempt count used as an optimistic lock.', Required => 1, HasValue => 1 );
    $Self->AddOption( Name => 'actor-user-id', Description => 'Tenant administrator performing the replay.', Required => 1, HasValue => 1 );
    $Self->AddOption( Name => 'confirm', Description => 'Confirm the external redelivery operation.', Required => 0, HasValue => 0 );
    return;
}

sub Run {
    my ($Self) = @_;
    if ( !$Self->GetOption('confirm') ) {
        $Self->PrintError('Refusing replay without --confirm.');
        return $Self->ExitCodeError();
    }
    my $UserID = $Self->GetOption('actor-user-id');
    my $Context = $Kernel::OM->Get('Kernel::System::D724::TenantDirectory')->ContextGet( UserID => $UserID );
    if ( !$Context->{Success} ) {
        $Self->PrintError("Actor context failed: $Context->{Error}");
        return $Self->ExitCodeError();
    }
    my $Result = $Kernel::OM->Get('Kernel::System::D724::EscalationDispatcher')->Replay(
        Subject => $Context->{Subject}, TenantID => $Self->GetOption('tenant-id'),
        OutboxID => $Self->GetOption('outbox-id'), ExpectedAttemptCount => $Self->GetOption('expected-attempt-count'),
    );
    if ( !$Result->{Success} ) {
        $Self->PrintError("Escalation replay failed: $Result->{Error}");
        return $Self->ExitCodeError();
    }
    $Self->Print("OutboxID=$Result->{Data}->{OutboxID} Status=$Result->{Data}->{Status} ReplayCount=$Result->{Data}->{ReplayCount}\n");
    return $Self->ExitCodeOk();
}

1;
