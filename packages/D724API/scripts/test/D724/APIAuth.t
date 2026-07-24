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
my $DB     = $Kernel::OM->Get('Kernel::System::DB');
my $API    = $Kernel::OM->Get('Kernel::System::D724::APIAuth');
my $Tenant = 'api-' . lc $Helper->GetRandomID();
my $Other  = 'api-other-' . lc $Helper->GetRandomID();

$Helper->ConfigSettingChange( Key => 'D724::API::Enabled', Value => 1 );
$Helper->ConfigSettingChange( Key => 'D724::API::BcryptCost', Value => 9 );
$Helper->ConfigSettingChange( Key => 'D724::API::TokenTTLMax', Value => 900 );
$Helper->ConfigSettingChange( Key => 'D724::API::RateLimitMax', Value => 100 );
$Helper->ConfigSettingChange( Key => 'D724::Audit::Enabled', Value => 1 );
$Helper->ConfigSettingChange( Key => 'D724::TenantGuard::Enabled', Value => 1 );

for my $TenantID ( $Tenant, $Other ) {
    my @Values = ( $TenantID, "API Test $TenantID", 1, 1 ); my @Bind = map { \$_ } @Values;
    ok( $DB->Do(
        SQL => "INSERT INTO d724_tenant (key_name, name, status, version, create_time, create_by, change_time, change_by) VALUES (?, ?, 'active', 1, current_timestamp, ?, current_timestamp, ?)",
        Bind => \@Bind,
    ), "tenant fixture $TenantID created" );
}

my $Admin = { ID => 'api-admin', TenantIDs => [$Tenant], RoleBindings => { $Tenant => ['tenant_admin'] } };
my $Created = $API->ClientCreate(
    Subject => $Admin, TenantID => $Tenant, Name => 'Acceptance Integration', Role => 'requester',
    UserID => 1, TokenTTL => 60, RateLimit => 2, ClientID => "integration-$Tenant",
);
ok( $Created->{Success}, 'tenant administrator creates API client' );
like( $Created->{Data}->{ClientSecret}, qr{\A[a-zA-Z0-9]{64}\z}, 'secret is high-entropy opaque material returned once' );

my $ClientID = $Created->{Data}->{ClientID}; my $Secret = $Created->{Data}->{ClientSecret};
$DB->Prepare( SQL => 'SELECT secret_hash FROM d724_api_client WHERE client_id = ?', Bind => [ \$ClientID ], Limit => 1 );
my ($StoredHash) = $DB->FetchrowArray();
like( $StoredHash, qr{\ABCRYPT:9:}, 'client secret is stored as bcrypt' );
isnt( $StoredHash, $Secret, 'plaintext secret is never stored' );

is( $API->TokenIssue( ClientID => $ClientID, ClientSecret => 'wrong-secret' )->{Error}, 'INVALID_CLIENT', 'wrong secret has generic client error' );
my $Issued = $API->TokenIssue( ClientID => $ClientID, ClientSecret => $Secret );
ok( $Issued->{Success}, 'valid client credentials issue token' );
is( $Issued->{Data}->{TokenType}, 'Bearer', 'token type is bearer' );
is( $Issued->{Data}->{ExpiresIn}, 60, 'configured short lifetime is returned' );
my $Token = $Issued->{Data}->{AccessToken};
like( $Token, qr{\A[a-zA-Z0-9]{64}\z}, 'opaque access token has expected format' );

$DB->Prepare( SQL => 'SELECT token_hash FROM d724_api_token WHERE client_id = ?', Bind => [ \$ClientID ], Limit => 1 );
my ($TokenHash) = $DB->FetchrowArray();
isnt( $TokenHash, $Token, 'plaintext bearer token is never stored' );
is( length $TokenHash, 64, 'only SHA-256 token digest is stored' );
ok( $API->TokenValidate( AccessToken => $Token )->{Success}, 'active token validates' );
is( $API->TokenValidate( AccessToken => 'x' x 64 )->{Error}, 'TOKEN_INVALID', 'unknown well-formed token fails closed' );

is(
    $API->ClientSecretRotate(
        Subject => $Admin, TenantID => $Tenant, ClientID => $ClientID,
        UserID => 1, ExpectedVersion => 99,
    )->{Error},
    'VERSION_CONFLICT', 'stale secret rotation version is rejected',
);
is(
    $API->ClientSecretRotate(
        Subject => { ID => 'other-admin', TenantIDs => [$Other], RoleBindings => { $Other => ['tenant_admin'] } },
        TenantID => $Other, ClientID => $ClientID, UserID => 1, ExpectedVersion => 1,
    )->{Error},
    'CLIENT_NOT_FOUND', 'cross-tenant secret rotation hides client existence',
);
$Helper->ConfigSettingChange( Key => 'D724::Audit::Enabled', Value => 0 );
is(
    $API->ClientSecretRotate(
        Subject => $Admin, TenantID => $Tenant, ClientID => $ClientID,
        UserID => 1, ExpectedVersion => 1,
    )->{Error},
    'AUDIT_WRITE_FAILED', 'secret rotation fails closed when audit is unavailable',
);
$DB->Prepare( SQL => 'SELECT secret_hash, version FROM d724_api_client WHERE client_id = ?', Bind => [ \$ClientID ], Limit => 1 );
my ( $HashAfterFailure, $VersionAfterFailure ) = $DB->FetchrowArray();
is( $HashAfterFailure, $StoredHash, 'failed rotation rolls secret hash back' );
is( $VersionAfterFailure, 1, 'failed rotation rolls version back' );
ok( $API->TokenValidate( AccessToken => $Token )->{Success}, 'failed rotation leaves existing token active' );
$Helper->ConfigSettingChange( Key => 'D724::Audit::Enabled', Value => 1 );

my $Rotated = $API->ClientSecretRotate(
    Subject => $Admin, TenantID => $Tenant, ClientID => $ClientID,
    UserID => 1, ExpectedVersion => 1,
);
ok( $Rotated->{Success}, 'tenant administrator rotates client secret' );
is( $Rotated->{Data}->{Version}, 2, 'secret rotation advances optimistic version' );
like( $Rotated->{Data}->{ClientSecret}, qr{\A[a-zA-Z0-9]{64}\z}, 'new secret is returned exactly as opaque material' );
isnt( $Rotated->{Data}->{ClientSecret}, $Secret, 'rotation produces different secret material' );
is( $API->TokenValidate( AccessToken => $Token )->{Error}, 'TOKEN_INVALID', 'rotation invalidates every existing token' );
is( $API->TokenIssue( ClientID => $ClientID, ClientSecret => $Secret )->{Error}, 'INVALID_CLIENT', 'old secret is invalid immediately' );
my $NewSecret = $Rotated->{Data}->{ClientSecret};
my $AfterRotateIssued = $API->TokenIssue( ClientID => $ClientID, ClientSecret => $NewSecret );
ok( $AfterRotateIssued->{Success}, 'new secret issues a token' );
$Token = $AfterRotateIssued->{Data}->{AccessToken};

is( $API->Authorize( AccessToken => $Token, TenantID => $Other, Action => 'case.read' )->{Error}, 'CROSS_TENANT', 'token cannot cross tenant' );
is( $API->Authorize( AccessToken => $Token, TenantID => $Tenant, Action => 'case.update' )->{Error}, 'FORBIDDEN', 'requester role cannot update cases' );
my $ReadOne = $API->Authorize( AccessToken => $Token, TenantID => $Tenant, Action => 'case.read' );
ok( $ReadOne->{Success}, 'first authorized request succeeds' );
is( $ReadOne->{Data}->{Remaining}, 1, 'first request consumes one rate unit' );
my $ReadTwo = $API->Authorize( AccessToken => $Token, TenantID => $Tenant, Action => 'catalog.read' );
ok( $ReadTwo->{Success}, 'second authorized request succeeds' );
is( $ReadTwo->{Data}->{Remaining}, 0, 'second request consumes final rate unit' );
is( $API->Authorize( AccessToken => $Token, TenantID => $Tenant, Action => 'case.read' )->{Error}, 'RATE_LIMITED', 'atomic per-minute limit fails closed' );

ok( $API->TokenRevoke( AccessToken => $Token )->{Success}, 'individual token revocation succeeds' );
is( $API->TokenValidate( AccessToken => $Token )->{Error}, 'TOKEN_INVALID', 'individually revoked token is immediately invalid' );
my $SecondIssued = $API->TokenIssue( ClientID => $ClientID, ClientSecret => $NewSecret );
ok( $SecondIssued->{Success}, 'second token issued before client revocation' );
my $SecondToken = $SecondIssued->{Data}->{AccessToken};
my $Revoked = $API->ClientRevoke( Subject => $Admin, TenantID => $Tenant, ClientID => $ClientID, UserID => 1 );
ok( $Revoked->{Success}, 'tenant administrator revokes API client' );
is( $Revoked->{Data}->{Version}, 3, 'client revocation advances optimistic version' );
is( $API->TokenValidate( AccessToken => $SecondToken )->{Error}, 'TOKEN_INVALID', 'client revocation immediately invalidates every active token' );
is( $API->ClientRevoke( Subject => $Admin, TenantID => $Tenant, ClientID => $ClientID, UserID => 1 )->{Data}->{Version}, 3, 'client revocation replay is idempotent' );
is( $API->ClientRevoke( Subject => { %{$Admin}, TenantIDs => [$Other], RoleBindings => { $Other => ['tenant_admin'] } }, TenantID => $Other, ClientID => $ClientID, UserID => 1 )->{Error}, 'CLIENT_NOT_FOUND', 'cross-tenant client lookup is hidden' );

my $Audit = $Kernel::OM->Get('Kernel::System::D724::Audit')->List( Subject => $Admin, TenantID => $Tenant, Limit => 100 );
is(
    [ map { $_->{Action} } grep { $_->{ObjectType} eq 'api_client' } @{ $Audit->{Data} } ],
    [
        'api.client.created', 'api.token.issued', 'api.client.secret_rotated',
        'api.token.issued', 'api.token.revoked', 'api.token.issued', 'api.client.revoked',
    ],
    'client, secret, and token lifecycle has ordered tenant audit evidence',
);

{
    local $Kernel::OM->Get('Kernel::Config')->{'D724::API::Enabled'} = 0;
    is( $API->TokenIssue( ClientID => $ClientID, ClientSecret => $NewSecret )->{Error}, 'API_DISABLED', 'disabled API fails closed' );
}

ok( $DB->Do( SQL => 'DELETE FROM d724_api_rate WHERE client_id = ?', Bind => [ \$ClientID ] ), 'rate fixtures removed' );
ok( $DB->Do( SQL => 'DELETE FROM d724_api_token WHERE client_id = ?', Bind => [ \$ClientID ] ), 'token fixtures removed' );
ok( $DB->Do( SQL => 'DELETE FROM d724_api_client WHERE client_id = ?', Bind => [ \$ClientID ] ), 'client fixture removed' );
ok( $DB->Do( SQL => 'DELETE FROM d724_audit_event WHERE tenant_id = ?', Bind => [ \$Tenant ] ), 'API audit fixture removed' );
ok( $DB->Do( SQL => 'DELETE FROM d724_audit_head WHERE tenant_id = ?', Bind => [ \$Tenant ] ), 'API audit head removed' );
for my $TenantID ( $Tenant, $Other ) {
    ok( $DB->Do( SQL => 'DELETE FROM d724_tenant WHERE key_name = ?', Bind => [ \$TenantID ] ), "tenant fixture $TenantID removed" );
}

done_testing;
