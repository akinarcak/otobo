# --
# D724 ESM is an enterprise service management platform based on OTOBO.
# Copyright (C) 2026 Data Market Bilgi Hizmetleri A.S.
# --
# This program is free software: you can redistribute it and/or modify it under
# the terms of the GNU General Public License as published by the Free Software
# Foundation, version 3 of the License.
# --

package Kernel::System::Console::Command::Admin::D724::FoundationStatus;

use v5.24;
use strict;
use warnings;

use parent qw(Kernel::System::Console::BaseCommand);

our @ObjectDependencies = (
    'Kernel::System::D724::Foundation',
    'Kernel::System::JSON',
);

sub Configure {
    my ( $Self, %Param ) = @_;

    $Self->Description('Validate the D724 ESM foundation and print its product manifest.');
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

    my $Status = $Kernel::OM->Get('Kernel::System::D724::Foundation')->StatusGet();

    if ( $Self->GetOption('json') ) {
        my $JSON = $Kernel::OM->Get('Kernel::System::JSON')->Encode(
            Data     => $Status,
            SortKeys => 1,
            Pretty   => 1,
        );
        $Self->Print($JSON);
    }
    else {
        my $Manifest = $Status->{Manifest};
        $Self->Print("D724 ESM foundation status\n");
        $Self->Print("Product: $Manifest->{Product}\n");
        $Self->Print("Edition: $Manifest->{Edition}\n");
        $Self->Print("Package: $Manifest->{Package} $Manifest->{PackageVersion}\n");
        $Self->Print("Framework: $Manifest->{FrameworkVersion}\n");
        $Self->Print("License: $Manifest->{License}\n");
        $Self->Print( $Status->{Success} ? "Status: OK\n" : "Status: FAILED\n" );
    }

    return $Status->{Success} ? $Self->ExitCodeOk() : $Self->ExitCodeError();
}

1;
