#!/usr/bin/env perl
# --
# Copyright (C) 2026 Data Market Bilgi Hizmetleri A.S.
# SPDX-License-Identifier: GPL-3.0-only
# --
use v5.24;
use strict;
use warnings;
use utf8;
use File::Path qw(make_path);
use JSON::PP ();
use Kernel::System::ObjectManager;

my $Target = shift // '/tmp/careoncloud-demo-reports';
my $From = shift // '2026-07-01';
my $To   = shift // '2026-07-31';
die "unsafe target path\n" if $Target !~ m{\A/tmp/[a-zA-Z0-9._/-]+\z}smx;
die "invalid date\n" if $From !~ m{\A\d{4}-\d{2}-\d{2}\z} || $To !~ m{\A\d{4}-\d{2}-\d{2}\z};
make_path($Target, { mode => 0750 });

local $Kernel::OM = Kernel::System::ObjectManager->new();
my $Reporting = $Kernel::OM->Get('Kernel::System::D724::Reporting');
my $Catalog   = $Kernel::OM->Get('Kernel::System::D724::Catalog');
my $Main = $Kernel::OM->Get('Kernel::System::Main');
$Kernel::OM->Get('Kernel::Config')->Set( Key => 'D724::TenantGuard::AllowPlatformAdmin', Value => 1 );
my $CatalogSubject = { ID => 'careoncloud-report-generator', Roles => ['platform_admin'], TenantIDs => ['reporting'] };
my @Tenant = (
    [ 'showcase-bank', 'Marmara Bank Demo' ],
    [ 'showcase-fashion', 'Anadolu Moda Demo' ],
    [ 'showcase-retail', 'Perakende360 Demo' ],
);
my @Summary;
for my $Tenant (@Tenant) {
    my ( $ID, $Name ) = @{$Tenant};
    my $JSON = $Reporting->Export(
        TenantID => $ID, From => $From, To => $To, UserID => 47, Format => 'json',
    );
    die "JSON report failed for $ID: $JSON->{Error}\n" if !$JSON->{Success};
    my $CSV = $Reporting->Export(
        TenantID => $ID, From => $From, To => $To, UserID => 47, Format => 'csv',
    );
    die "CSV report failed for $ID: $CSV->{Error}\n" if !$CSV->{Success};
    my $Services = $Catalog->ServiceList( Subject => $CatalogSubject, TenantID => $ID );
    die "catalog service list failed for $ID: $Services->{Error}\n" if !$Services->{Success};
    my ( $OfferingCount, $AvailableItemCount ) = ( 0, 0 );
    for my $Service ( @{ $Services->{Data} } ) {
        my $Offerings = $Catalog->OfferingList(
            Subject => $CatalogSubject, TenantID => $ID, ServiceID => $Service->{ServiceID},
        );
        die "catalog offering list failed for $ID: $Offerings->{Error}\n" if !$Offerings->{Success};
        $OfferingCount += scalar @{ $Offerings->{Data} };
        for my $Offering ( @{ $Offerings->{Data} } ) {
            my $Items = $Catalog->CatalogItemList(
                Subject => $CatalogSubject, TenantID => $ID, OfferingID => $Offering->{OfferingID},
            );
            die "catalog item list failed for $ID: $Items->{Error}\n" if !$Items->{Success};
            $AvailableItemCount += scalar grep { $_->{Status} eq 'active' } @{ $Items->{Data} };
        }
    }
    for my $File (
        [ "$Target/$ID-operational.json", $JSON->{Content} ],
        [ "$Target/$ID-operational.csv",  $CSV->{Content} ],
    ) {
        my $Content = $File->[1];
        die "write failed: $File->[0]\n" if !$Main->FileWrite(
            Location => $File->[0], Content => \$Content, Mode => 'utf8', Type => 'Local', Permission => '640',
        );
    }
    push @Summary, {
        tenant_id => $ID, tenant_name => $Name, synthetic => JSON::PP::true,
        totals => $JSON->{Data}->{Totals}, request_status => $JSON->{Data}->{RequestStatus},
        catalog_usage => $JSON->{Data}->{CatalogItems}, commitment_status => $JSON->{Data}->{CommitmentStatus},
        catalog_capacity => {
            services => scalar @{ $Services->{Data} }, offerings => $OfferingCount,
            active_items => $AvailableItemCount,
        },
    };
}
my %Overall = ( requests => 0, commitments => 0, breached_commitments => 0 );
for my $Tenant (@Summary) {
    $Overall{requests} += $Tenant->{totals}->{Requests};
    $Overall{commitments} += $Tenant->{totals}->{Commitments};
    $Overall{breached_commitments} += $Tenant->{totals}->{BreachedCommitments};
}
my $Executive = JSON::PP->new->canonical->pretty->encode({
    product => 'CareOnCloud ESM', slogan => 'Hizmet Bulutta, Kontrol Sizde.',
    disclaimer => 'Tamamen sentetik satış demosudur; gerçek müşteri veya referans değildir.',
    from => $From, to => $To, overall => \%Overall, tenants => \@Summary,
});
die "executive summary write failed\n" if !$Main->FileWrite(
    Location => "$Target/executive-summary.json", Content => \$Executive,
    Mode => 'utf8', Type => 'Local', Permission => '640',
);
say JSON::PP->new->canonical->encode({ success => JSON::PP::true, target => $Target, files => 7, overall => \%Overall });
