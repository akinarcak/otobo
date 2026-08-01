# --
# CareOnCloud ESM enterprise service management platform.
# Copyright (C) 2026 Data Market Bilgi Hizmetleri A.S.
# SPDX-License-Identifier: GPL-3.0-only
# --

use v5.24;
use strict;
use warnings;
use utf8;

use Test2::V0;
use Kernel::System::UnitTest::RegisterOM;

my $FoundationObject = $Kernel::OM->Get('Kernel::System::D724::Foundation');
my $ConfigObject     = $Kernel::OM->Get('Kernel::Config');

my $Manifest = $FoundationObject->ManifestGet();
is( $Manifest->{Product}, 'CareOnCloud ESM', 'product identity is available' );
is( $Manifest->{Slogan}, 'Hizmet Bulutta, Kontrol Sizde.', 'brand slogan is available' );
is( $Manifest->{Edition}, 'Community', 'default edition is Community' );
is( $Manifest->{Package}, 'D724Foundation', 'package name is stable' );
is( $Manifest->{PackageVersion}, '0.2.1', 'package version is exposed' );
is( $Manifest->{License}, 'GPL-3.0-only', 'license is explicit' );
ok( $Manifest->{FrameworkVersion}, 'framework version is exposed' );

my $Status = $FoundationObject->StatusGet();
ok( $Status->{Success}, 'foundation status succeeds with valid defaults' );
ok( !$Status->{TelemetryEnabled}, 'telemetry is opt-in' );

{
    local $ConfigObject->{'D724::Foundation::Enabled'} = 0;
    my $DisabledStatus = $FoundationObject->StatusGet();
    ok( !$DisabledStatus->{Success}, 'disabled foundation fails the readiness status' );
    ok( !$DisabledStatus->{Checks}->{Enabled}, 'enabled check reports the cause' );
}

done_testing;
