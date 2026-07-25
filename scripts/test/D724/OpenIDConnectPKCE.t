# --
# Copyright (C) 2026 Data Market Bilgi Hizmetleri A.S.
# SPDX-License-Identifier: GPL-3.0-only
# --
use v5.24;
use strict;
use warnings;

use Test2::V0;
use URI ();
use Kernel::System::UnitTest::RegisterOM;

my $OAuth2 = $Kernel::OM->Get('Kernel::System::OpenIDConnect::OAuth2');
my $OIDC   = $Kernel::OM->Get('Kernel::System::OpenIDConnect');

my $Challenge = 'A' x 43;
my $Verifier  = 'v' x 64;

my $URL = $OAuth2->GetAuthURL(
    AuthorizationEndpoint => 'https://login.example.invalid/authorize',
    ClientID              => 'careoncloud-client',
    Scope                 => 'openid profile email',
    ResponseType          => ['code'],
    RedirectURL           => 'https://esm.example.invalid/otobo/index.pl',
    State                 => 'state-value',
    CodeChallenge         => $Challenge,
    CodeChallengeMethod   => 'S256',
);
my $URI = URI->new($URL);
my %Query = $URI->query_form();
is( $Query{code_challenge},        $Challenge, 'authorization URL carries exact PKCE challenge' );
is( $Query{code_challenge_method}, 'S256',     'authorization URL requires S256' );

ok(
    !$OAuth2->GetAuthURL(
        AuthorizationEndpoint => 'https://login.example.invalid/authorize',
        ClientID              => 'careoncloud-client',
        Scope                 => 'openid',
        ResponseType          => ['code'],
        RedirectURL           => 'https://esm.example.invalid/otobo/index.pl',
        State                 => 'state-value',
        CodeChallenge         => $Challenge,
        CodeChallengeMethod   => 'plain',
    ),
    'plain PKCE challenge method is rejected',
);

my $CapturedPostData;
{
    no warnings 'redefine';
    local *Kernel::System::OpenIDConnect::OAuth2::_SendRequest = sub {
        my ( $Self, %Param ) = @_;
        $CapturedPostData = $Param{PostData};
        return { Success => 1, Content => { id_token => 'signed-token' } };
    };

    my $Token = $OAuth2->RequestToken(
        TokenEndpoint => 'https://login.example.invalid/token',
        ClientID      => 'careoncloud-client',
        ClientSecret  => 'client-secret',
        GrantType     => 'authorization_code',
        Code          => 'authorization-code',
        RedirectURL   => 'https://esm.example.invalid/otobo/index.pl',
        CodeVerifier  => $Verifier,
    );
    ok( $Token->{Success}, 'authorization code exchange succeeds' );
}
my %Post = @{$CapturedPostData};
is( $Post{code_verifier}, $Verifier, 'token request carries exact PKCE verifier' );

my $SendCalled = 0;
{
    no warnings 'redefine';
    local *Kernel::System::OpenIDConnect::OAuth2::_SendRequest = sub {
        $SendCalled = 1;
        return { Success => 1, Content => {} };
    };
    my $Token = $OAuth2->RequestToken(
        TokenEndpoint => 'https://login.example.invalid/token',
        ClientID      => 'careoncloud-client',
        ClientSecret  => 'client-secret',
        GrantType     => 'authorization_code',
        Code          => 'authorization-code',
        RedirectURL   => 'https://esm.example.invalid/otobo/index.pl',
        CodeVerifier  => 'too-short',
    );
    ok( !$Token->{Success}, 'invalid verifier is rejected' );
}
ok( !$SendCalled, 'invalid verifier is never sent to the provider' );

my $Forwarded;
{
    no warnings 'redefine';
    local *Kernel::System::OpenIDConnect::Configuration::GetTokenEndpoint = sub {
        return 'https://login.example.invalid/token';
    };
    local *Kernel::System::OpenIDConnect::OAuth2::RequestToken = sub {
        my ( $Self, %Param ) = @_;
        $Forwarded = \%Param;
        return { Success => 1, DecodedContent => { id_token => 'signed-token' } };
    };
    my $IDToken = $OIDC->RequestIDToken(
        AuthorizationCode => 'authorization-code',
        CodeVerifier      => $Verifier,
        ClientSettings    => {
            ClientID => 'careoncloud-client', ClientSecret => 'client-secret',
            RedirectURI => 'https://esm.example.invalid/otobo/index.pl',
        },
        ProviderSettings => { OpenIDConfiguration => 'https://login.example.invalid/.well-known/openid-configuration' },
    );
    is( $IDToken, 'signed-token', 'OpenIDConnect wrapper returns ID token' );
}
is( $Forwarded->{CodeVerifier}, $Verifier, 'OpenIDConnect wrapper forwards PKCE verifier' );

done_testing;
