# --
# Copyright (C) 2026 Data Market Bilgi Hizmetleri A.S.
# SPDX-License-Identifier: GPL-3.0-only
# --
package Kernel::System::Console::Command::Admin::CareOnCloud::ReportingStatus;
use v5.24;
use strict;
use warnings;
use parent qw(Kernel::System::Console::BaseCommand);

our $VERSION = '0.4.1';
our @ObjectDependencies = ('Kernel::Config', 'Kernel::System::DB', 'Kernel::System::JSON');

sub Configure {
    my ($Self) = @_;
    $Self->Description('Validate CareOnCloud tenant-safe reporting dependencies and configuration.');
    $Self->AddOption( Name => 'json', Description => 'Print JSON.', Required => 0, HasValue => 0 );
    return;
}

sub StatusData {
    my ($Self) = @_;
    my $DB = $Kernel::OM->Get('Kernel::System::DB');
    my %Existing = map { $_ => 1 } $DB->ListTables();
    my %Tables = map { $_ => $Existing{$_} ? 1 : 0 } qw(careoncloud_tenant careoncloud_tenant_agent_role careoncloud_catalog_item careoncloud_request careoncloud_commitment_instance);
    my $Config = $Kernel::OM->Get('Kernel::Config');
    my $Enabled = $Config->Get('CareOnCloud::Reporting::Enabled') ? 1 : 0;
    my $Maximum = $Config->Get('CareOnCloud::Reporting::MaximumRangeDays') // 366;
    my $CacheTTL = $Config->Get('CareOnCloud::Reporting::CacheTTLSeconds') // 60;
    my $ConfigValid = $Maximum =~ m{\A[1-9][0-9]{0,3}\z}smx && $CacheTTL =~ m{\A[1-9][0-9]{0,4}\z}smx ? 1 : 0;
    my $Success = $Enabled && $ConfigValid && !( grep { !$_ } values %Tables );
    return {
        Success => $Success ? 1 : 0, Package => 'CareOnCloudReporting', Version => $VERSION,
        Enabled => $Enabled, MaximumRangeDays => 0 + $Maximum, CacheTTLSeconds => 0 + $CacheTTL, ConfigValid => $ConfigValid, Tables => \%Tables,
    };
}

sub Run {
    my ($Self) = @_;
    my $Status = $Self->StatusData();
    if ( $Self->GetOption('json') ) {
        $Self->Print( $Kernel::OM->Get('Kernel::System::JSON')->Encode( Data => $Status, SortKeys => 1, Pretty => 1 ) );
    }
    else { $Self->Print( 'CareOnCloud reporting status: ' . ( $Status->{Success} ? 'OK' : 'FAILED' ) . "\n" ) }
    return $Status->{Success} ? $Self->ExitCodeOk() : $Self->ExitCodeError();
}
1;
