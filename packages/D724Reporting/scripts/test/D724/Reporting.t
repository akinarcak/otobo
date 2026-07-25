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
for my $Setting ( [ 'D724::Reporting::Enabled', 1 ], [ 'D724::Reporting::MaximumRangeDays', 366 ], [ 'D724::Catalog::Enabled', 1 ] ) {
    $Helper->ConfigSettingChange( Key => $Setting->[0], Value => $Setting->[1] );
}
my $Suffix = lc $Helper->GetRandomID();
my $TenantA = "report-a-$Suffix";
my $TenantB = "report-b-$Suffix";
my $DB = $Kernel::OM->Get('Kernel::System::DB');
for my $Tenant ( $TenantA, $TenantB ) {
    my @Value = ( $Tenant, "Report $Tenant", 'active', 1, 1, 1 ); my @Bind = map { \$_ } @Value;
    ok( $DB->Do(
        SQL => 'INSERT INTO d724_tenant (key_name, name, status, version, create_time, create_by, change_time, change_by) VALUES (?, ?, ?, ?, current_timestamp, ?, current_timestamp, ?)',
        Bind => \@Bind,
    ), "tenant $Tenant created" );
}

my $Catalog = $Kernel::OM->Get('Kernel::System::D724::Catalog');
my %Items;
for my $Fixture ( [ $TenantA, '=Formula Safe' ], [ $TenantB, 'Secret Tenant B' ] ) {
    my ( $Tenant, $Name ) = @{$Fixture};
    my $Subject = { ID => "admin:$Tenant", TenantIDs => [$Tenant], RoleBindings => { $Tenant => ['tenant_admin'] } };
    my %Call = ( Subject => $Subject, TenantID => $Tenant, UserID => 1 );
    my $Service = $Catalog->ServiceCreate( %Call, Key => 'it', Name => 'IT', Status => 'active' );
    my $Offering = $Catalog->OfferingCreate( %Call, ServiceID => $Service->{Data}->{ServiceID}, Key => 'support', Name => 'Support', Status => 'active' );
    my $Item = $Catalog->CatalogItemCreate( %Call, OfferingID => $Offering->{Data}->{OfferingID}, Key => 'help', Name => $Name, Status => 'active' );
    ok( $Item->{Success}, "catalog fixture for $Tenant created" );
    $Items{$Tenant} = $Item->{Data}->{CatalogItemID};
}

my $InsertRequest = sub {
    my ( $Tenant, $Number, $Created ) = @_;
    my @Value = ( $Number, $Tenant, $Items{$Tenant}, "requester-$Tenant", "idem-$Number", 'a' x 64, '{}', '{}', 'fulfilled', 1, $Created, 'test', $Created, 'test' );
    my @Bind = map { \$_ } @Value;
    return $DB->Do(
        SQL => 'INSERT INTO d724_request (request_number, tenant_id, catalog_item_id, requester_id, idempotency_key, payload_hash, answers_json, workflow_json, status, version, create_time, create_by, change_time, change_by) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        Bind => \@Bind,
    );
};
ok( $InsertRequest->( $TenantA, "RPT-A-$Suffix", '2026-07-10 12:00:00' ), 'tenant A in-range request inserted' );
ok( $InsertRequest->( $TenantA, "RPT-A-OLD-$Suffix", '2025-01-01 12:00:00' ), 'tenant A out-of-range request inserted' );
ok( $InsertRequest->( $TenantB, "RPT-B-$Suffix", '2026-07-10 12:00:00' ), 'tenant B secret request inserted' );

my $Reporting = $Kernel::OM->Get('Kernel::System::D724::Reporting');
my $OwnerA = { ID => 'owner-a', TenantIDs => [$TenantA], RoleBindings => { $TenantA => ['service_owner'] } };
my $AuditorA = { ID => 'auditor-a', TenantIDs => [$TenantA], RoleBindings => { $TenantA => ['auditor'] } };
my $AgentA = { ID => 'agent-a', TenantIDs => [$TenantA], RoleBindings => { $TenantA => ['agent'] } };
my $OwnerB = { ID => 'owner-b', TenantIDs => [$TenantB], RoleBindings => { $TenantB => ['service_owner'] } };

my %Range = ( TenantID => $TenantA, From => '2026-07-01', To => '2026-07-31' );
my $Summary = $Reporting->Summary( Subject => $OwnerA, %Range );
ok( $Summary->{Success}, 'service owner reads tenant operational summary' );
is( $Summary->{Data}->{Totals}->{Requests}, 1, 'date range includes exactly one own-tenant request' );
is( $Summary->{Data}->{CatalogItems}->[0]->{Name}, '=Formula Safe', 'summary retains catalog label without requester PII' );
is( $Reporting->Summary( Subject => $OwnerB, %Range )->{Error}, 'FORBIDDEN', 'cross-tenant report read is denied' );
is( $Reporting->Summary( Subject => $AgentA, %Range )->{Error}, 'FORBIDDEN', 'ordinary agent cannot read management report' );
ok( $Reporting->Summary( Subject => $AuditorA, %Range )->{Success}, 'auditor can read privacy-minimized report' );

my $CSV = $Reporting->Export( Subject => $OwnerA, %Range, Format => 'csv' );
ok( $CSV->{Success}, 'service owner exports CSV' );
is( $CSV->{ContentType}, 'text/csv; charset=utf-8', 'CSV media type is explicit' );
like( $CSV->{Content}, qr{"'=Formula Safe"}, 'spreadsheet formula injection is neutralized' );
unlike( $CSV->{Content}, qr{Secret Tenant B}, 'CSV contains no cross-tenant catalog label' );
unlike( $CSV->{Content}, qr{requester-}, 'CSV excludes requester identity' );

my $JSON = $Reporting->Export( Subject => $AuditorA, %Range, Format => 'json' );
ok( $JSON->{Success}, 'auditor exports JSON' );
unlike( $JSON->{Content}, qr{idem-|requester-}, 'JSON excludes idempotency keys and requester identities' );
is( $Reporting->Export( Subject => $AgentA, %Range, Format => 'csv' )->{Error}, 'FORBIDDEN', 'agent cannot export report' );
is( $Reporting->Export( Subject => $OwnerA, %Range, Format => 'xml' )->{Error}, 'FORMAT_INVALID', 'unknown export format is rejected' );
is( $Reporting->Summary( Subject => $OwnerA, %Range, From => '2026-99-99' )->{Error}, 'DATE_INVALID', 'invalid calendar date is rejected' );
is( $Reporting->Summary( Subject => $OwnerA, TenantID => $TenantA, From => '2025-01-01', To => '2026-12-31' )->{Error}, 'RANGE_TOO_LARGE', 'oversized report range is rejected' );

$Helper->ConfigSettingChange( Key => 'D724::Reporting::Enabled', Value => 0 );
is( $Reporting->Summary( Subject => $OwnerA, %Range )->{Error}, 'REPORTING_DISABLED', 'disabled reporting fails closed' );

done_testing;
