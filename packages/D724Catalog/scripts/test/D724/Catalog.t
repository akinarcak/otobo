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
    'Kernel::System::UnitTest::Helper' => {
        RestoreDatabase => 1,
    },
);
my $Helper = $Kernel::OM->Get('Kernel::System::UnitTest::Helper');
$Helper->ConfigSettingChange(
    Key   => 'D724::Catalog::Enabled',
    Value => 1,
);

my $Catalog = $Kernel::OM->Get('Kernel::System::D724::Catalog');
my $AdminA  = { ID => 'admin-a', Roles => ['tenant_admin'], TenantIDs => ['tenant-a'] };
my $AdminB  = { ID => 'admin-b', Roles => ['tenant_admin'], TenantIDs => ['tenant-b'] };
my $ReaderA = { ID => 'reader-a', Roles => ['requester'],    TenantIDs => ['tenant-a'] };
my %BaseA   = ( Subject => $AdminA, TenantID => 'tenant-a', UserID => 1 );

my $ServiceA = $Catalog->ServiceCreate(
    %BaseA,
    Key         => 'workplace',
    Name        => 'Workplace Services',
    Description => 'Tenant A workplace portfolio.',
    Status      => 'active',
);
ok( $ServiceA->{Success}, 'tenant A service is created' );
is( $ServiceA->{Data}->{Version}, 1, 'new service starts at version 1' );

my $ServiceB = $Catalog->ServiceCreate(
    Subject     => $AdminB,
    TenantID    => 'tenant-b',
    UserID      => 1,
    Key         => 'workplace',
    Name        => 'Tenant B Workplace',
    Description => q{},
);
ok( $ServiceB->{Success}, 'same key can exist in another tenant' );

my $OwnRead = $Catalog->ServiceGet(
    Subject   => $ReaderA,
    TenantID  => 'tenant-a',
    UserID    => 1,
    ServiceID => $ServiceA->{Data}->{ServiceID},
);
is( $OwnRead->{Data}->{Name}, 'Workplace Services', 'requester reads own tenant service' );

my $CrossTenant = $Catalog->ServiceGet(
    Subject   => $ReaderA,
    TenantID  => 'tenant-b',
    UserID    => 1,
    ServiceID => $ServiceB->{Data}->{ServiceID},
);
is( $CrossTenant->{Error}, 'FORBIDDEN', 'explicit cross-tenant read is forbidden' );
is( $CrossTenant->{Reason}, 'DENY_CROSS_TENANT', 'cross-tenant denial reason is preserved' );

my $HiddenID = $Catalog->ServiceGet(
    Subject   => $ReaderA,
    TenantID  => 'tenant-a',
    UserID    => 1,
    ServiceID => $ServiceB->{Data}->{ServiceID},
);
is( $HiddenID->{Error}, 'NOT_FOUND', 'foreign tenant ID is invisible in own scope' );

my $ReaderWrite = $Catalog->ServiceCreate(
    Subject  => $ReaderA,
    TenantID => 'tenant-a',
    UserID   => 1,
    Key      => 'forbidden',
    Name     => 'Forbidden',
);
is( $ReaderWrite->{Error}, 'FORBIDDEN', 'requester cannot manage catalog' );
is( $ReaderWrite->{Reason}, 'DENY_ROLE_NOT_GRANTED', 'role denial is explicit' );

my $BadParent = $Catalog->OfferingCreate(
    %BaseA,
    ServiceID => $ServiceB->{Data}->{ServiceID},
    Key       => 'bad-parent',
    Name      => 'Bad parent',
);
is( $BadParent->{Error}, 'PARENT_NOT_FOUND', 'cross-tenant service cannot be used as parent' );

my $Offering = $Catalog->OfferingCreate(
    %BaseA,
    ServiceID      => $ServiceA->{Data}->{ServiceID},
    Key            => 'standard-device',
    Name           => 'Standard Device',
    Status         => 'active',
    FulfillmentType => 'process',
);
ok( $Offering->{Success}, 'offering is created under own service' );

my $Item = $Catalog->CatalogItemCreate(
    %BaseA,
    OfferingID => $Offering->{Data}->{OfferingID},
    Key        => 'request-laptop',
    Name       => 'Request a laptop',
    Status     => 'active',
    RequestType => 'service_request',
);
ok( $Item->{Success}, 'catalog item is created under own offering' );

my $List = $Catalog->ServiceList(
    Subject  => $ReaderA,
    TenantID => 'tenant-a',
    UserID   => 1,
    Status   => 'active',
);
is( scalar @{ $List->{Data} }, 1, 'list is tenant and status scoped' );
is( $List->{Data}->[0]->{TenantID}, 'tenant-a', 'list never leaks tenant B' );

my $ItemList = $Catalog->CatalogItemList(
    Subject    => $ReaderA,
    TenantID   => 'tenant-a',
    UserID     => 1,
    OfferingID => $Offering->{Data}->{OfferingID},
);
is( [ map { $_->{Key} } @{ $ItemList->{Data} } ], ['request-laptop'], 'item list honors parent filter' );

my $Updated = $Catalog->ServiceUpdate(
    %BaseA,
    ServiceID      => $ServiceA->{Data}->{ServiceID},
    ExpectedVersion => 1,
    Name           => 'Digital Workplace Services',
);
ok( $Updated->{Success}, 'matching version updates service' );
is( $Updated->{Data}->{Version}, 2, 'update increments version' );

my $Stale = $Catalog->ServiceUpdate(
    %BaseA,
    ServiceID      => $ServiceA->{Data}->{ServiceID},
    ExpectedVersion => 1,
    Name           => 'Stale overwrite',
);
is( $Stale->{Error}, 'VERSION_CONFLICT', 'stale update is rejected' );
my $AfterStale = $Catalog->ServiceGet(
    Subject => $ReaderA, TenantID => 'tenant-a', UserID => 1,
    ServiceID => $ServiceA->{Data}->{ServiceID},
);
is( $AfterStale->{Data}->{Name}, 'Digital Workplace Services', 'stale update does not overwrite data' );

is(
    $Catalog->ServiceCreate( %BaseA, Key => 'workplace', Name => 'Duplicate' )->{Error},
    'KEY_EXISTS',
    'duplicate tenant key is rejected',
);
is(
    $Catalog->ServiceCreate( %BaseA, Key => 'Bad Key', Name => 'Invalid' )->{Error},
    'KEY_INVALID',
    'invalid key is rejected',
);
is(
    $Catalog->ServiceCreate( %BaseA, Key => 'invalid-status', Name => 'Invalid', Status => 'deleted' )->{Error},
    'STATUS_INVALID',
    'invalid lifecycle status is rejected',
);
is(
    $Catalog->OfferingCreate(
        %BaseA, ServiceID => $ServiceA->{Data}->{ServiceID}, Key => 'invalid-type',
        Name => 'Invalid', FulfillmentType => 'magic',
    )->{Error},
    'FULFILLMENT_TYPE_INVALID',
    'invalid fulfillment type is rejected',
);

{
    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');
    local $ConfigObject->{'D724::Catalog::Enabled'} = 0;
    is(
        $Catalog->ServiceList( Subject => $ReaderA, TenantID => 'tenant-a', UserID => 1 )->{Error},
        'CATALOG_DISABLED',
        'disabled catalog fails closed',
    );
}

done_testing;
