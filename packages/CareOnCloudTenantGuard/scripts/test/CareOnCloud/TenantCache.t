# --
# Copyright (C) 2026 Data Market Bilgi Hizmetleri A.S.
# SPDX-License-Identifier: GPL-3.0-only
# --
use v5.24;
use strict;
use warnings;
use Test2::V0;
use Kernel::System::UnitTest::RegisterOM;

$Kernel::OM->ObjectParamAdd( 'Kernel::System::UnitTest::Helper' => { RestoreDatabase => 1 } );
my $Helper = $Kernel::OM->Get('Kernel::System::UnitTest::Helper');
$Helper->ConfigSettingChange( Key => 'CareOnCloud::TenantCache::Enabled', Value => 1 );
$Helper->ConfigSettingChange( Key => 'CareOnCloud::TenantCache::MaximumTTLSeconds', Value => 600 );
my $Suffix = lc $Helper->GetRandomID();
my $TenantA = "cache-a-$Suffix";
my $TenantB = "cache-b-$Suffix";
my $DB = $Kernel::OM->Get('Kernel::System::DB');
for my $Tenant ( $TenantA, $TenantB ) {
    my @Value = ( $Tenant, "Cache $Tenant", 'active', 1, 1, 1 ); my @Bind = map { \$_ } @Value;
    ok( $DB->Do(
        SQL => 'INSERT INTO careoncloud_tenant (key_name, name, status, version, create_time, create_by, change_time, change_by) VALUES (?, ?, ?, ?, current_timestamp, ?, current_timestamp, ?)',
        Bind => \@Bind,
    ), "tenant $Tenant created" );
}
my $Cache = $Kernel::OM->Get('Kernel::System::CareOnCloud::TenantCache');
my $SubjectA = { ID => 'cache-a', TenantIDs => [$TenantA], RoleBindings => { $TenantA => ['requester'] } };
my $SubjectB = { ID => 'cache-b', TenantIDs => [$TenantB], RoleBindings => { $TenantB => ['requester'] } };
my %A = ( Subject => $SubjectA, TenantID => $TenantA, Action => 'catalog.read', Domain => 'catalog', Key => 'same-logical-key' );
my %B = ( Subject => $SubjectB, TenantID => $TenantB, Action => 'catalog.read', Domain => 'catalog', Key => 'same-logical-key' );

ok( $Cache->Set( %A, Value => 'tenant-a-value', TTL => 300 )->{Success}, 'tenant A value is cached' );
ok( $Cache->Set( %B, Value => 'tenant-b-value', TTL => 300 )->{Success}, 'same logical key is cached for tenant B' );
is( $Cache->Get(%A)->{Value}, 'tenant-a-value', 'tenant A reads only its cached value' );
is( $Cache->Get(%B)->{Value}, 'tenant-b-value', 'tenant B reads only its cached value' );

my $NamespaceA = $Cache->NamespaceGet( TenantID => $TenantA, Domain => 'catalog', Key => 'same-logical-key' );
my $NamespaceB = $Cache->NamespaceGet( TenantID => $TenantB, Domain => 'catalog', Key => 'same-logical-key' );
isnt( $NamespaceA->{Type}, $NamespaceB->{Type}, 'physical cache types are tenant-separated' );
unlike( $NamespaceA->{Type} . $NamespaceA->{Key}, qr{\Q$TenantA\E}, 'physical cache address does not disclose tenant identifier' );
is( $Cache->Get( %A, Subject => $SubjectB )->{Error}, 'FORBIDDEN', 'cross-tenant subject cannot read another namespace' );
is( $Cache->Set( %A, Value => 'x', TTL => 601 )->{Error}, 'TTL_INVALID', 'TTL above configured maximum is rejected' );
is( $Cache->Set( %A, Key => "bad\nkey", Value => 'x' )->{Error}, 'KEY_INVALID', 'control-character key injection is rejected' );
is( $Cache->Set( %A, Domain => '../catalog', Value => 'x' )->{Error}, 'DOMAIN_INVALID', 'domain path injection is rejected' );

ok( $Cache->Delete(%A)->{Success}, 'single tenant cache key is invalidated' );
ok( !$Cache->Get(%A)->{Hit}, 'deleted tenant A key misses' );
is( $Cache->Get(%B)->{Value}, 'tenant-b-value', 'tenant A invalidation cannot delete tenant B value' );
ok( $Cache->Set( %A, Key => 'one', Value => 1 )->{Success}, 'tenant A first cleanup fixture set' );
ok( $Cache->Set( %A, Key => 'two', Value => 2 )->{Success}, 'tenant A second cleanup fixture set' );
ok( $Cache->TenantCleanUp(%A)->{Success}, 'tenant-wide cache invalidation succeeds' );
ok( !$Cache->Get( %A, Key => 'one' )->{Hit} && !$Cache->Get( %A, Key => 'two' )->{Hit}, 'tenant-wide invalidation removes all tenant A domains/keys' );
is( $Cache->Get(%B)->{Value}, 'tenant-b-value', 'tenant-wide invalidation remains isolated from tenant B' );

my $Inactive = 'inactive';
ok( $DB->Do( SQL => 'UPDATE careoncloud_tenant SET status = ? WHERE key_name = ?', Bind => [ \$Inactive, \$TenantA ] ), 'tenant A deactivated' );
is( $Cache->Get(%A)->{Error}, 'TENANT_INACTIVE', 'inactive tenant cache access fails closed' );
ok( $Cache->TenantCleanUp(%B)->{Success}, 'tenant B cache fixture cleaned' );
$Helper->ConfigSettingChange( Key => 'CareOnCloud::TenantCache::Enabled', Value => 0 );
is( $Cache->Get(%B)->{Error}, 'CACHE_DISABLED', 'disabled cache adapter fails closed' );

done_testing;
