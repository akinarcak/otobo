# --
# Copyright (C) 2026 Data Market Bilgi Hizmetleri A.S.
# SPDX-License-Identifier: GPL-3.0-only
# --
package Kernel::System::Console::Command::Admin::D724::TenantCacheStatus;

use v5.24;
use strict;
use warnings;
use parent qw(Kernel::System::Console::BaseCommand);

our $VERSION = '0.1.0';
our @ObjectDependencies = ('Kernel::Config', 'Kernel::System::Cache', 'Kernel::System::JSON');

sub Configure {
    my ($Self) = @_;
    $Self->Description('Validate the CareOnCloud tenant cache adapter and persistent backend configuration.');
    $Self->AddOption( Name => 'json', Description => 'Print JSON.', Required => 0, HasValue => 0 );
    return;
}

sub StatusData {
    my ($Self) = @_;
    my $Config = $Kernel::OM->Get('Kernel::Config');
    my $Enabled = $Config->Get('D724::TenantCache::Enabled') ? 1 : 0;
    my $Maximum = $Config->Get('D724::TenantCache::MaximumTTLSeconds') // 86400;
    my $MaximumValid = $Maximum =~ m{\A[1-9][0-9]{0,5}\z}smx ? 1 : 0;
    my $Backend = $Config->Get('Cache::Module') // q{};
    my $BackendAvailable = eval { $Kernel::OM->Get('Kernel::System::Cache'); 1 } ? 1 : 0;
    my $Success = $Enabled && $MaximumValid && length($Backend) && $BackendAvailable;
    return {
        Success => $Success ? 1 : 0,
        Package => 'D724TenantGuard',
        AdapterVersion => '0.1.0',
        Enabled => $Enabled,
        MaximumTTLSeconds => $MaximumValid ? 0 + $Maximum : "$Maximum",
        MaximumTTLValid => $MaximumValid,
        BackendModule => $Backend,
        BackendAvailable => $BackendAvailable,
        NamespaceVersion => 1,
        PersistentOnly => 1,
    };
}

sub Run {
    my ($Self) = @_;
    my $Status = $Self->StatusData();
    if ( $Self->GetOption('json') ) {
        $Self->Print( $Kernel::OM->Get('Kernel::System::JSON')->Encode( Data => $Status, SortKeys => 1, Pretty => 1 ) );
    }
    else { $Self->Print( 'CareOnCloud tenant cache status: ' . ( $Status->{Success} ? 'OK' : 'FAILED' ) . "\n" ) }
    return $Status->{Success} ? $Self->ExitCodeOk() : $Self->ExitCodeError();
}

1;
