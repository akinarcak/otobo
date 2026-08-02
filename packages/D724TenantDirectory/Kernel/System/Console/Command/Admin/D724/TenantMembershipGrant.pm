# --
# CareOnCloud ESM enterprise service management platform.
# Copyright (C) 2026 Data Market Bilgi Hizmetleri A.S.
# SPDX-License-Identifier: GPL-3.0-only
# --

package Kernel::System::Console::Command::Admin::D724::TenantMembershipGrant;

use v5.24;
use strict;
use warnings;
use parent qw(Kernel::System::Console::BaseCommand);

our @ObjectDependencies = (
    'Kernel::System::D724::TenantDirectory',
    'Kernel::System::User',
);

sub Configure {
    my ($Self) = @_;
    $Self->Description('Grant a tenant-bound CareOnCloud role using an existing tenant administrator context.');
    $Self->AddOption( Name => 'tenant-id', Description => 'Tenant identifier.', Required => 1, HasValue => 1, ValueRegex => qr{[a-zA-Z0-9][a-zA-Z0-9._:-]{0,127}}smx );
    $Self->AddOption( Name => 'actor-user-id', Description => 'Existing authorized agent user ID.', Required => 1, HasValue => 1, ValueRegex => qr{[1-9][0-9]*}smx );
    $Self->AddOption( Name => 'member-login', Description => 'Existing agent login receiving the role.', Required => 1, HasValue => 1, ValueRegex => qr{.+}smx );
    $Self->AddOption( Name => 'role', Description => 'Tenant role.', Required => 1, HasValue => 1, ValueRegex => qr{requester|agent|service_owner|auditor|tenant_admin}smx );
    return;
}

sub Run {
    my ($Self) = @_;
    my $Directory = $Kernel::OM->Get('Kernel::System::D724::TenantDirectory');
    my $ActorUserID = $Self->GetOption('actor-user-id');
    my $MemberUserID = $Kernel::OM->Get('Kernel::System::User')->UserLookup(
        UserLogin => $Self->GetOption('member-login'), Silent => 1,
    );
    if (!$MemberUserID) {
        $Self->PrintError('Member agent login was not found.');
        return $Self->ExitCodeError();
    }
    my $Context = $Directory->ContextGet( UserID => $ActorUserID );
    if (!$Context->{Success}) {
        $Self->PrintError( "Actor context failed: $Context->{Error}" );
        return $Self->ExitCodeError();
    }
    my $Result = $Directory->MembershipGrant(
        Subject      => $Context->{Subject},
        TenantID     => $Self->GetOption('tenant-id'),
        MemberUserID => $MemberUserID,
        Role         => $Self->GetOption('role'),
        UserID       => $ActorUserID,
    );
    if (!$Result->{Success}) {
        $Self->PrintError( "Membership grant failed: $Result->{Error}" );
        return $Self->ExitCodeError();
    }
    $Self->Print("Tenant membership granted.\n");
    return $Self->ExitCodeOk();
}

1;
