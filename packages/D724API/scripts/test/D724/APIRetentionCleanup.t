# --
# Copyright (C) 2026 Data Market Bilgi Hizmetleri A.S.
# SPDX-License-Identifier: GPL-3.0-only
# --
use v5.24;
use strict;
use warnings;
use Capture::Tiny qw(capture);
use Test2::V0;
use Kernel::System::UnitTest::RegisterOM;

$Kernel::OM->ObjectParamAdd( 'Kernel::System::UnitTest::Helper' => { RestoreDatabase => 1 } );
my $Helper = $Kernel::OM->Get('Kernel::System::UnitTest::Helper');
my $DB = $Kernel::OM->Get('Kernel::System::DB');
my $Suffix = lc $Helper->GetRandomID();
my $Tenant = "retention-$Suffix";
my $Client = "retention-client-$Suffix";
my $TokenHash = 'a' x 64;
$Helper->ConfigSettingChange( Key => 'D724::API::TokenRetentionDays', Value => 30 );
$Helper->ConfigSettingChange( Key => 'D724::API::RateRetentionHours', Value => 48 );

my @TenantValues = ( $Tenant, "Retention $Tenant", 1, 1 );
my @TenantBind = map { \$_ } @TenantValues;
ok( $DB->Do(
    SQL => "INSERT INTO d724_tenant (key_name, name, status, version, create_time, create_by, change_time, change_by) VALUES (?, ?, 'active', 1, current_timestamp, ?, current_timestamp, ?)",
    Bind => \@TenantBind,
), 'retention tenant fixture created' );
my @ClientValues = ( $Client, $Tenant, 'Retention fixture', 'BCRYPT:9:1234567890123456:fixture', 'requester', 'revoked', 60, 10, 1, 1 );
my @ClientBind = map { \$_ } @ClientValues;
ok( $DB->Do(
    SQL => 'INSERT INTO d724_api_client (client_id, tenant_id, name, secret_hash, role_name, status, token_ttl, rate_limit, version, create_time, create_by, change_time, change_by) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 1, current_timestamp, ?, current_timestamp, ?)',
    Bind => \@ClientBind,
), 'retention client fixture created' );
my @TokenValues = ( $TokenHash, $Client );
my @TokenBind = map { \$_ } @TokenValues;
ok( $DB->Do(
    SQL => "INSERT INTO d724_api_token (token_hash, client_id, expires_at, status, create_time) VALUES (?, ?, DATE_SUB(current_timestamp, INTERVAL 40 DAY), 'revoked', DATE_SUB(current_timestamp, INTERVAL 40 DAY))",
    Bind => \@TokenBind,
), 'stale token digest fixture created' );
ok( $DB->Do(
    SQL => "INSERT INTO d724_api_rate (client_id, window_start, request_count) VALUES (?, DATE_SUB(current_timestamp, INTERVAL 72 HOUR), 3)",
    Bind => [ \$Client ],
), 'stale rate window fixture created' );

my $Command = $Kernel::OM->Get('Kernel::System::Console::Command::Maint::D724::APIRetentionCleanup');
my ( $Output, undef, $ExitCode ) = capture { return $Command->Execute('--confirm') };
is( $ExitCode, 0, 'retention cleanup command succeeds' );
like( $Output, qr{DeletedTokenDigests=1}, 'cleanup reports deleted token digest' );
like( $Output, qr{DeletedRateWindows=1}, 'cleanup reports deleted rate window' );
$DB->Prepare( SQL => 'SELECT COUNT(*) FROM d724_api_token WHERE token_hash = ?', Bind => [ \$TokenHash ] );
my ($Tokens) = $DB->FetchrowArray();
is( $Tokens, 0, 'stale token digest is deleted' );
$DB->Prepare( SQL => 'SELECT COUNT(*) FROM d724_api_rate WHERE client_id = ?', Bind => [ \$Client ] );
my ($Rates) = $DB->FetchrowArray();
is( $Rates, 0, 'stale rate window is deleted' );

ok( $DB->Do( SQL => 'DELETE FROM d724_api_client WHERE client_id = ?', Bind => [ \$Client ] ), 'client fixture removed' );
ok( $DB->Do( SQL => 'DELETE FROM d724_tenant WHERE key_name = ?', Bind => [ \$Tenant ] ), 'tenant fixture removed' );

done_testing;
