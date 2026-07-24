# --
# D724 ESM is an enterprise service management platform based on OTOBO.
# Copyright (C) 2026 Data Market Bilgi Hizmetleri A.S.
# SPDX-License-Identifier: GPL-3.0-only
# --

use v5.24;
use strict;
use warnings;
use utf8;

use Test2::V0;
use Kernel::System::UnitTest::RegisterOM;

$Kernel::OM->ObjectParamAdd(
    'Kernel::System::UnitTest::Helper' => { RestoreDatabase => 1 },
);
my $Helper = $Kernel::OM->Get('Kernel::System::UnitTest::Helper');
$Helper->ConfigSettingChange( Key => 'D724::Catalog::Enabled', Value => 1 );

my $Catalog = $Kernel::OM->Get('Kernel::System::D724::Catalog');
my $Portal  = $Kernel::OM->Get('Kernel::System::D724::CatalogPortal');
my $Admin   = { ID => 'portal-admin', Roles => ['tenant_admin'], TenantIDs => ['portal-tenant'] };
my %Write   = ( Subject => $Admin, TenantID => 'portal-tenant', UserID => 1 );

my $Service = $Catalog->ServiceCreate(
    %Write, Key => 'portal-service', Name => 'Portal Service', Status => 'active',
);
my $Offering = $Catalog->OfferingCreate(
    %Write, ServiceID => $Service->{Data}->{ServiceID}, Key => 'portal-offering',
    Name => 'Portal Offering', Status => 'active',
);
my $Item = $Catalog->CatalogItemCreate(
    %Write, OfferingID => $Offering->{Data}->{OfferingID}, Key => 'portal-item',
    Name => 'Portal Item', Status => 'active',
);
$Catalog->CatalogItemSchemaSet(
    %Write, CatalogItemID => $Item->{Data}->{CatalogItemID},
    Schema => { version => 1, fields => [ { key => 'summary', label => 'Summary', type => 'text', required => 1 } ] },
);
$Catalog->CatalogItemCreate(
    %Write, OfferingID => $Offering->{Data}->{OfferingID}, Key => 'draft-item',
    Name => 'Draft Item', Status => 'draft',
);

my $View = $Portal->CatalogGet(
    CustomerUserID => 'portal.user@example.com', CustomerID => 'portal-tenant', TenantID => 'ignored-attacker-input',
);
ok( $View->{Success}, 'authenticated customer catalog view succeeds' );
is( $View->{TenantID}, 'portal-tenant', 'tenant comes only from trusted customer context' );
is( $View->{Data}->[0]->{Offerings}->[0]->{Items}->[0]->{Key}, 'portal-item', 'only active item is visible' );
is( scalar @{ $View->{Data}->[0]->{Offerings}->[0]->{Items} }, 1, 'draft item is excluded from portal' );

my $Detail = $Portal->ItemGet(
    CustomerUserID => 'portal.user', CustomerID => 'portal-tenant',
    CatalogItemID => $Item->{Data}->{CatalogItemID},
);
is( $Detail->{Data}->{FormSchema}->{Schema}->{fields}->[0]->{key}, 'summary', 'portal detail contains dynamic form schema' );

$Catalog->OfferingUpdate(
    %Write, OfferingID => $Offering->{Data}->{OfferingID}, ExpectedVersion => 1, Status => 'suspended',
);
is(
    $Portal->ItemGet(
        CustomerUserID => 'portal.user', CustomerID => 'portal-tenant',
        CatalogItemID => $Item->{Data}->{CatalogItemID},
    )->{Error},
    'NOT_AVAILABLE',
    'active item is unavailable when its parent offering is suspended',
);

is(
    $Portal->CatalogGet( CustomerUserID => 'portal.user' )->{Error},
    'CUSTOMER_TENANT_MISSING',
    'missing authenticated customer tenant fails closed',
);
is(
    $Portal->ItemGet(
        CustomerUserID => 'other.user', CustomerID => 'other-tenant',
        CatalogItemID => $Item->{Data}->{CatalogItemID},
    )->{Error},
    'NOT_FOUND',
    'foreign tenant item ID remains invisible',
);

done_testing;
