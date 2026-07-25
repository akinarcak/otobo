# --
# Copyright (C) 2026 Data Market Bilgi Hizmetleri A.S.
# SPDX-License-Identifier: GPL-3.0-only
# --
use v5.24; use strict; use warnings; use Test2::V0; use Kernel::System::UnitTest::RegisterOM;
my $Helper=$Kernel::OM->Get('Kernel::System::UnitTest::Helper');
$Helper->ConfigSettingChange(Key=>'D724::Observability::Enabled',Value=>1);
$Helper->ConfigSettingChange(Key=>'D724::SearchPolicy::Enabled',Value=>1);
$Helper->ConfigSettingChange(Key=>'D724::TenantCache::Enabled',Value=>1);
$Helper->ConfigSettingChange(Key=>'Elasticsearch::Active',Value=>1);
my $Service=$Kernel::OM->Get('Kernel::System::D724::Observability');
my $Status=$Service->StatusData();
ok($Status->{Success},'consolidated probe succeeds');
is($Status->{MissingTables},[],'all authoritative health tables are installed');
is($Status->{SeriesCount},20,'series cardinality is fixed');
my $Text=$Service->PrometheusRender(Status=>$Status);
my @Names=$Service->MetricNames();
is(scalar @Names,20,'metric registry has the expected fixed size');
for my $Name (@Names) { like($Text,qr/^\Q$Name\E [0-9]+(?:\.[0-9]+)?$/m,"$Name is rendered") }
unlike($Text,qr/\{[^}]+\}/,'no dynamic labels are exported');
unlike($Text,qr/(?:tenant_id|user_id|route|request_id|customer)/i,'no sensitive dimension names are exported');
is(scalar(()=$Text=~/^# TYPE /mg),20,'each metric has one type declaration');
done_testing;
