#!/usr/bin/env perl
# --
# Copyright (C) 2026 Data Market Bilgi Hizmetleri A.S.
# SPDX-License-Identifier: GPL-3.0-only
# --
use v5.24;
use strict;
use warnings;
use File::Spec ();
use Kernel::System::ObjectManager;

my ( $SourcePath, $ModuleDirectory, $TargetDirectory ) = @ARGV;
die "Usage: Build-Package.pl SOURCE.sopm MODULE_DIRECTORY TARGET_DIRECTORY\n"
    if !defined $TargetDirectory;
die "Package source is not readable: $SourcePath\n" if !-r $SourcePath;
die "Module directory does not exist: $ModuleDirectory\n" if !-d $ModuleDirectory;
die "Target directory does not exist: $TargetDirectory\n" if !-d $TargetDirectory;

local $Kernel::OM = Kernel::System::ObjectManager->new();
my $Main = $Kernel::OM->Get('Kernel::System::Main');
my $ContentRef = $Main->FileRead(
    Location => $SourcePath, Mode => 'utf8', Result => 'SCALAR',
);
die "Package source could not be read: $SourcePath\n"
    if !$ContentRef || ref $ContentRef ne 'SCALAR';

my %Structure = $Kernel::OM->Get('Kernel::System::Package')->PackageParse(
    String => ${$ContentRef},
);
die "Invalid package metadata\n"
    if !$Structure{Name}->{Content} || !$Structure{Version}->{Content};
$Structure{Home} = $ModuleDirectory;
my $Package = $Kernel::OM->Get('Kernel::System::Package')->PackageBuild(%Structure);
die "Package build failed\n" if !$Package;

my $PackageName    = $Structure{Name}->{Content};
my $PackageVersion = $Structure{Version}->{Content};
my $Filename       = "$PackageName-$PackageVersion.opm";
my $Location = File::Spec->catfile( $TargetDirectory, $Filename );
my $Written = $Main->FileWrite(
    Location => $Location, Content => \$Package, Mode => 'utf8',
    Type => 'Local', Permission => '644',
);
die "Package could not be written: $Location\n" if !$Written;
say $Location;
