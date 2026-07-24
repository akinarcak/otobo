# --
# D724 ESM is an enterprise service management platform based on OTOBO.
# Copyright (C) 2026 Data Market Bilgi Hizmetleri A.S.
# SPDX-License-Identifier: GPL-3.0-only
# --

package Kernel::System::Console::Command::Admin::D724::CatalogStatus;

use v5.24;
use strict;
use warnings;

use parent qw(Kernel::System::Console::BaseCommand);

our @ObjectDependencies = (
    'Kernel::Config',
    'Kernel::System::DB',
    'Kernel::System::JSON',
);

sub Configure {
    my ( $Self, %Param ) = @_;

    $Self->Description('Validate the D724 tenant-safe service catalog repository.');
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

    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');
    my $DBObject     = $Kernel::OM->Get('Kernel::System::DB');
    my %Existing     = map { $_ => 1 } $DBObject->ListTables();
    my %Tables       = map { $_ => $Existing{$_} ? 1 : 0 }
        qw(d724_service d724_service_offering d724_catalog_item d724_catalog_item_schema);
    my $Enabled = $ConfigObject->Get('D724::Catalog::Enabled') ? 1 : 0;
    my $Success = $Enabled && !grep { !$Tables{$_} } keys %Tables;
    my $Status  = {
        Success => $Success ? 1 : 0,
        Enabled => $Enabled,
        Package => 'D724Catalog',
        Version => '0.2.1',
        Tables  => \%Tables,
    };

    if ( $Self->GetOption('json') ) {
        $Self->Print(
            $Kernel::OM->Get('Kernel::System::JSON')->Encode(
                Data     => $Status,
                SortKeys => 1,
                Pretty   => 1,
            )
        );
    }
    else {
        $Self->Print("D724 service catalog status\n");
        $Self->Print( 'Repository: ' . ( $Enabled ? 'enabled' : 'disabled' ) . "\n" );
        for my $Table ( sort keys %Tables ) {
            $Self->Print( "$Table: " . ( $Tables{$Table} ? 'OK' : 'MISSING' ) . "\n" );
        }
        $Self->Print( $Success ? "Status: OK\n" : "Status: FAILED\n" );
    }

    return $Success ? $Self->ExitCodeOk() : $Self->ExitCodeError();
}

1;
