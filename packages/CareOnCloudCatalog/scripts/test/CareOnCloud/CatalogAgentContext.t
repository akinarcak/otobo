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

$Kernel::OM->ObjectParamAdd( 'Kernel::System::UnitTest::Helper' => { RestoreDatabase => 1 } );
my $Helper = $Kernel::OM->Get('Kernel::System::UnitTest::Helper');
$Helper->ConfigSettingChange( Key => 'CareOnCloud::TenantGuard::Enabled', Value => 1 );
$Helper->ConfigSettingChange( Key => 'CareOnCloud::TenantGuard::AllowPlatformAdmin', Value => 1 );

my $Directory = $Kernel::OM->Get('Kernel::System::CareOnCloud::TenantDirectory');
my $Catalog   = $Kernel::OM->Get('Kernel::System::CareOnCloud::Catalog');
my $Platform  = { ID => 'catalog-platform-test', Roles => ['platform_admin'], TenantIDs => ['bootstrap'] };
my $Suffix    = $Helper->GetRandomID();
my $TenantA   = "catalog-admin-a-$Suffix";
my $TenantB   = "catalog-admin-b-$Suffix";
$Directory->TenantCreate( Subject => $Platform, TenantID => $TenantA, Name => 'Catalog Admin A', UserID => 1 );
$Directory->TenantCreate( Subject => $Platform, TenantID => $TenantB, Name => 'Catalog Admin B', UserID => 1 );
my $AdminA = { ID => 'grant-a', TenantIDs => [$TenantA], RoleBindings => { $TenantA => ['tenant_admin'] } };
my $AdminB = { ID => 'grant-b', TenantIDs => [$TenantB], RoleBindings => { $TenantB => ['tenant_admin'] } };
$Directory->MembershipGrant(
    Subject => $AdminA, TenantID => $TenantA, MemberUserID => 1, Role => 'tenant_admin', UserID => 1,
);
$Directory->MembershipGrant(
    Subject => $AdminB, TenantID => $TenantB, MemberUserID => 1, Role => 'requester', UserID => 1,
);
my $Context = $Directory->ContextGet( UserID => 1 );

ok(
    $Catalog->ServiceCreate(
        Subject => $Context->{Subject}, TenantID => $TenantA, UserID => 1,
        Key => 'managed-service', Name => 'Managed Service',
    )->{Success},
    'directory-derived tenant admin context can manage its catalog',
);
is(
    $Catalog->ServiceCreate(
        Subject => $Context->{Subject}, TenantID => $TenantB, UserID => 1,
        Key => 'forbidden-service', Name => 'Forbidden Service',
    )->{Reason},
    'DENY_ROLE_NOT_GRANTED',
    'directory-derived requester context cannot manage another tenant catalog',
);
is(
    $Catalog->ServiceList( Subject => $Context->{Subject}, TenantID => $TenantB )->{Data},
    [],
    'requester can read its tenant without seeing tenant A catalog records',
);

my $Layout = $Kernel::OM->Get('Kernel::Output::HTML::Layout');
$Layout->Block(
    Name => 'ServiceRow',
    Data => {
        TenantID => $TenantA, ServiceID => 1, Version => 1, Key => 'escaped',
        Name => 'Managed <script>alert(1)</script>', Description => 'Description', Status => 'draft',
    },
);
my $HTML = $Layout->Output( TemplateFile => 'AdminCareOnCloudCatalog', Data => { TenantID => $TenantA } );
like( $HTML, qr{Managed\s*&lt;script&gt;alert\(1\)&lt;/script&gt;}, 'admin catalog template escapes names' );
unlike( $HTML, qr{<script>alert\(1\)</script>}, 'admin catalog template never emits untrusted markup' );
like( $HTML, qr{name="ChallengeToken"}, 'admin write forms include CSRF challenge token' );

done_testing;
