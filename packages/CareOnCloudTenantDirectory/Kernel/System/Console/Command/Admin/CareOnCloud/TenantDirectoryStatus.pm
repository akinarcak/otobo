# --
# CareOnCloud ESM enterprise service management platform.
# Copyright (C) 2026 Data Market Bilgi Hizmetleri A.S.
# SPDX-License-Identifier: GPL-3.0-only
# --

package Kernel::System::Console::Command::Admin::CareOnCloud::TenantDirectoryStatus;

use v5.24;
use strict;
use warnings;
use parent qw(Kernel::System::Console::BaseCommand);

our @ObjectDependencies = ('Kernel::System::DB', 'Kernel::System::JSON');

sub Configure {
    my ($Self) = @_;
    $Self->Description('Validate the CareOnCloud tenant directory schema and print counts.');
    $Self->AddOption( Name => 'json', Description => 'Print JSON.', Required => 0, HasValue => 0 );
    return;
}

sub Run {
    my ($Self) = @_;
    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');
    my %Existing = map { $_ => 1 } $DBObject->ListTables();
    my %Tables = map { $_ => $Existing{$_} ? 1 : 0 } qw(careoncloud_tenant careoncloud_tenant_agent_role);
    my %Counts = ( Tenants => 0, ActiveMemberships => 0 );
    if ( $Tables{careoncloud_tenant} ) {
        $DBObject->Prepare( SQL => 'SELECT COUNT(*) FROM careoncloud_tenant' );
        ($Counts{Tenants}) = $DBObject->FetchrowArray();
    }
    if ( $Tables{careoncloud_tenant_agent_role} ) {
        $DBObject->Prepare( SQL => "SELECT COUNT(*) FROM careoncloud_tenant_agent_role WHERE status = 'active'" );
        ($Counts{ActiveMemberships}) = $DBObject->FetchrowArray();
    }
    my $Success = !( grep { !$_ } values %Tables );
    my $Status = { Success => $Success ? 1 : 0, Package => 'CareOnCloudTenantDirectory', Version => '0.2.1', Tables => \%Tables, Counts => \%Counts };
    if ( $Self->GetOption('json') ) {
        $Self->Print( $Kernel::OM->Get('Kernel::System::JSON')->Encode( Data => $Status, SortKeys => 1, Pretty => 1 ) );
    }
    else {
        $Self->Print("CareOnCloud tenant directory status\nTenants: $Counts{Tenants}\nActive memberships: $Counts{ActiveMemberships}\n");
        $Self->Print( $Success ? "Status: OK\n" : "Status: FAILED\n" );
    }
    return $Success ? $Self->ExitCodeOk() : $Self->ExitCodeError();
}

1;
