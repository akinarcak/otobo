# --
# D724 ESM is an enterprise service management platform based on OTOBO.
# Copyright (C) 2026 Data Market Bilgi Hizmetleri A.S.
# --
# This program is free software: you can redistribute it and/or modify it under
# the terms of the GNU General Public License as published by the Free Software
# Foundation, version 3 of the License.
# --

package Kernel::System::D724::Foundation;

use v5.24;
use strict;
use warnings;

our $VERSION = '0.1.0';

our @ObjectDependencies = (
    'Kernel::Config',
);

sub new {
    my ($Type) = @_;

    return bless {}, $Type;
}

sub ManifestGet {
    my ($Self) = @_;

    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');

    return {
        Product          => $ConfigObject->Get('D724::Foundation::ProductName') // q{},
        Edition          => $ConfigObject->Get('D724::Foundation::Edition') // q{},
        Package          => 'D724Foundation',
        PackageVersion   => $VERSION,
        FrameworkVersion => $ConfigObject->Get('Version') // q{},
        License          => 'GPL-3.0-only',
        Capabilities     => [
            'product-identity',
            'foundation-diagnostics',
            'feature-configuration',
        ],
    };
}

sub StatusGet {
    my ($Self) = @_;

    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');
    my $Manifest     = $Self->ManifestGet();

    my $Enabled = $ConfigObject->Get('D724::Foundation::Enabled') ? 1 : 0;
    my %Checks  = (
        Enabled          => $Enabled,
        ProductName      => $Manifest->{Product} ? 1 : 0,
        Edition          => $Manifest->{Edition} ? 1 : 0,
        FrameworkVersion => $Manifest->{FrameworkVersion} ? 1 : 0,
        License          => $Manifest->{License} eq 'GPL-3.0-only' ? 1 : 0,
    );

    my $Success = 1;
    for my $Check ( values %Checks ) {
        $Success = 0 if !$Check;
    }

    return {
        Success  => $Success,
        Checks   => \%Checks,
        Manifest => $Manifest,
        TelemetryEnabled => $ConfigObject->Get('D724::Foundation::TelemetryEnabled') ? 1 : 0,
    };
}

1;
