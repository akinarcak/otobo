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
my $DB = $Kernel::OM->Get('Kernel::System::DB');
my $Status = $Kernel::OM->Get('Kernel::System::D724::CatalogConstraint')->Ensure();
ok( $Status->{Success}, 'all catalog parent relations have tenant-paired database constraints' );
ok( $Status->{UniqueItemTenantID}, 'catalog item exposes the composite parent key' );
is(
    [ sort grep { $Status->{Constraints}->{$_} } keys %{ $Status->{Constraints} } ],
    [qw(d724_fk_item_offering_tenant d724_fk_offering_service_tenant d724_fk_schema_item_tenant)],
    'three composite tenant foreign keys are present and structurally exact',
);

my $Suffix = lc $Helper->GetRandomID();
my ( $TenantA, $TenantB ) = ( "constraint-a-$Suffix", "constraint-b-$Suffix" );
for my $TenantID ( $TenantA, $TenantB ) {
    my @Value = ( $TenantID, "Constraint $TenantID", 1, 1 );
    my @Bind = map { \$_ } @Value;
    ok( $DB->Do(
        SQL => q{INSERT INTO d724_tenant (key_name,name,status,version,create_time,create_by,change_time,change_by) VALUES (?,?,'active',1,current_timestamp,?,current_timestamp,?)},
        Bind => \@Bind,
    ), "fixture tenant $TenantID created" );
}
my @ServiceValue = ( $TenantA, "service-$Suffix", 1, 1 );
my @ServiceBind = map { \$_ } @ServiceValue;
ok( $DB->Do(
    SQL => q{INSERT INTO d724_service (tenant_id,key_name,name,description,status,version,create_time,create_by,change_time,change_by) VALUES (?,?,'Service','fixture','active',1,current_timestamp,?,current_timestamp,?)},
    Bind => \@ServiceBind,
), 'same-tenant parent service fixture created' );
$DB->Prepare( SQL => 'SELECT id FROM d724_service WHERE tenant_id = ? AND key_name = ?', Bind => [ \$TenantA, \$ServiceValue[1] ], Limit => 1 );
my ($ServiceID) = $DB->FetchrowArray();

my @CrossValue = ( $TenantB, $ServiceID, "offering-$Suffix", 1, 1 );
my @CrossBind = map { \$_ } @CrossValue;
ok( !$DB->Do(
    SQL => q{INSERT INTO d724_service_offering (tenant_id,service_id,key_name,name,description,status,fulfillment_type,version,create_time,create_by,change_time,change_by) VALUES (?,?,?,'Cross tenant','must fail','active','process',1,current_timestamp,?,current_timestamp,?)},
    Bind => \@CrossBind,
), 'database rejects a direct cross-tenant offering-to-service relation' );

done_testing;
