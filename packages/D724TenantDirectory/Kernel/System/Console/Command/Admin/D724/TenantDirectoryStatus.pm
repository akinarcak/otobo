# --
# D724 ESM is an enterprise service management platform based on OTOBO.
# Copyright (C) 2026 Data Market Bilgi Hizmetleri A.S.
# SPDX-License-Identifier: GPL-3.0-only
# --

package Kernel::System::Console::Command::Admin::D724::TenantDirectoryStatus;

use v5.24;
use strict;
use warnings;
use parent qw(Kernel::System::Console::BaseCommand);

our @ObjectDependencies = ('Kernel::System::DB', 'Kernel::System::JSON');

sub Configure {
    my ($Self) = @_;
    $Self->Description('Validate the D724 tenant directory schema and print counts.');
    $Self->AddOption( Name => 'json', Description => 'Print JSON.', Required => 0, HasValue => 0 );
    return;
}

sub Run {
    my ($Self) = @_;
    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');
    my %Existing = map { $_ => 1 } $DBObject->ListTables();
    my %Tables = map { $_ => $Existing{$_} ? 1 : 0 } qw(d724_tenant d724_tenant_agent_role);
    my %Counts = ( Tenants => 0, ActiveMemberships => 0 );
    if ( $Tables{d724_tenant} ) {
        $DBObject->Prepare( SQL => 'SELECT COUNT(*) FROM d724_tenant' );
        ($Counts{Tenants}) = $DBObject->FetchrowArray();
    }
    if ( $Tables{d724_tenant_agent_role} ) {
        $DBObject->Prepare( SQL => "SELECT COUNT(*) FROM d724_tenant_agent_role WHERE status = 'active'" );
        ($Counts{ActiveMemberships}) = $DBObject->FetchrowArray();
    }
    my $Success = !( grep { !$_ } values %Tables );
    my $Status = { Success => $Success ? 1 : 0, Package => 'D724TenantDirectory', Version => '0.1.2', Tables => \%Tables, Counts => \%Counts };
    if ( $Self->GetOption('json') ) {
        $Self->Print( $Kernel::OM->Get('Kernel::System::JSON')->Encode( Data => $Status, SortKeys => 1, Pretty => 1 ) );
    }
    else {
        $Self->Print("D724 tenant directory status\nTenants: $Counts{Tenants}\nActive memberships: $Counts{ActiveMemberships}\n");
        $Self->Print( $Success ? "Status: OK\n" : "Status: FAILED\n" );
    }
    return $Success ? $Self->ExitCodeOk() : $Self->ExitCodeError();
}

1;
