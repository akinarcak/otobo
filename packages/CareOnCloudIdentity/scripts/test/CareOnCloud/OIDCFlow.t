# --
# Copyright (C) 2026 Data Market Bilgi Hizmetleri A.S.
# SPDX-License-Identifier: GPL-3.0-only
# --
use v5.24;use strict;use warnings;
use Test2::V0;use Digest::SHA qw(sha256);use MIME::Base64 qw(encode_base64url);use Kernel::System::UnitTest::RegisterOM;
$Kernel::OM->ObjectParamAdd('Kernel::System::UnitTest::Helper'=>{RestoreDatabase=>1});my$H=$Kernel::OM->Get('Kernel::System::UnitTest::Helper');
$H->ConfigSettingChange(Key=>'CareOnCloud::Identity::Enabled',Value=>1);$H->ConfigSettingChange(Key=>'CareOnCloud::TenantGuard::Enabled',Value=>1);$H->ConfigSettingChange(Key=>'CareOnCloud::TenantGuard::AllowPlatformAdmin',Value=>1);
my$I=$Kernel::OM->Get('Kernel::System::CareOnCloud::Identity');my$F=$Kernel::OM->Get('Kernel::System::CareOnCloud::OIDCFlow');my$D=$Kernel::OM->Get('Kernel::System::CareOnCloud::TenantDirectory');my$DB=$Kernel::OM->Get('Kernel::System::DB');
$Kernel::OM->Get('Kernel::System::OpenIDConnect::Token'); # Load the class before locally replacing Validate below.
my$S=lc$H->GetRandomID();my$T="oidc-$S";my$Issuer="https://login.example.invalid/$S";my$Audience="client-$S";my$P={ID=>'platform',Roles=>['platform_admin'],TenantIDs=>['bootstrap']};
ok($D->TenantCreate(Subject=>$P,TenantID=>$T,Name=>'OIDC',UserID=>1)->{Success},'tenant created');my$Admin={ID=>'admin',TenantIDs=>[$T],RoleBindings=>{$T=>['tenant_admin']}};
ok($I->ProviderCreate(Subject=>$Admin,TenantID=>$T,Key=>'oidc',Issuer=>$Issuer,Audience=>$Audience,AllowedDomains=>['example.com'],GroupRoleMap=>{'agents'=>'agent'},UserID=>1)->{Success},'provider created');
is($F->Begin(TenantID=>$T,ProviderKey=>'oidc',BrowserBinding=>'b'x40,ReturnPath=>'https://evil.invalid')->{Error},'RETURN_PATH_INVALID','external return URL rejected');
my$Flow=$F->Begin(TenantID=>$T,ProviderKey=>'oidc',BrowserBinding=>'b'x40,ReturnPath=>'/careoncloud/index.pl');ok($Flow->{Success},'OIDC flow begins');
is($Flow->{Data}->{CodeChallenge},encode_base64url(sha256($Flow->{Data}->{CodeVerifier})),'PKCE challenge is exact S256');
$DB->Prepare(SQL=>'SELECT state_digest,nonce_digest,verifier_digest,status FROM careoncloud_oidc_flow WHERE tenant_id=?',Bind=>[\$T],Limit=>1);my@Stored=$DB->FetchrowArray();
unlike(join('|',@Stored),qr/\Q$Flow->{Data}->{State}\E|\Q$Flow->{Data}->{Nonce}\E|\Q$Flow->{Data}->{CodeVerifier}\E/,'database stores only flow secret digests');is($Stored[3],'pending','flow starts pending');
is($F->ExchangeContextGet(State=>$Flow->{Data}->{State},BrowserBinding=>'wrong browser binding value xxxxx',CodeVerifier=>$Flow->{Data}->{CodeVerifier})->{Error},'BROWSER_BINDING_MISMATCH','exchange context rejects wrong browser binding');
my$Context=$F->ExchangeContextGet(State=>$Flow->{Data}->{State},BrowserBinding=>'b'x40,CodeVerifier=>$Flow->{Data}->{CodeVerifier});ok($Context->{Success},'verified pending exchange context is available');is($Context->{Data}->{TenantID},$T,'exchange context tenant comes from stored flow');is($Context->{Data}->{ProviderKey},'oidc','exchange context provider comes from stored flow');
my$Provider=$I->ProviderRouteGetByKey(TenantID=>$T,ProviderKey=>'oidc');my$Metadata={issuer=>$Issuer,authorization_endpoint=>"$Issuer/authorize",token_endpoint=>"$Issuer/token",jwks_uri=>"$Issuer/jwks",id_token_signing_alg_values_supported=>[qw(RS256 HS256)]};
ok($F->MetadataValidate(Provider=>$Provider,Metadata=>$Metadata)->{Success},'same-origin HTTPS metadata and asymmetric algorithm accepted');
is($F->MetadataValidate(Provider=>$Provider,Metadata=>{%$Metadata,jwks_uri=>'https://evil.invalid/jwks'})->{Error},'JWKS_URI_INVALID','cross-origin JWKS rejected');
is($F->MetadataValidate(Provider=>$Provider,Metadata=>{%$Metadata,id_token_signing_alg_values_supported=>['HS256']})->{Error},'SIGNING_ALGORITHM_UNSUPPORTED','symmetric-only ID token algorithms rejected');
my$Claims={iss=>$Issuer,aud=>$Audience,sub=>'oidc-subject',preferred_username=>'oidc.user',email=>'oidc.user@example.com',groups=>['agents'],nonce=>$Flow->{Data}->{Nonce},exp=>time+300,iat=>time};
my $MockClaims = $Claims;
no warnings 'redefine'; local *Kernel::System::OpenIDConnect::Token::Validate=sub{return{Success=>1,TokenData=>$MockClaims}};
my%Callback=(State=>$Flow->{Data}->{State},BrowserBinding=>'b'x40,CodeVerifier=>$Flow->{Data}->{CodeVerifier},IDToken=>'signed.jwt.value',OpenIDConfig=>{ClientSettings=>{ClientID=>$Audience}});
is($F->CallbackVerify(%Callback,CodeVerifier=>'x'x43)->{Error},'PKCE_VERIFIER_MISMATCH','wrong PKCE verifier rejected without consuming flow');
my$WrongNonce={%$Claims,nonce=>'wrong'}; $MockClaims=$WrongNonce;
is($F->CallbackVerify(%Callback)->{Error},'TOKEN_NONCE_MISMATCH','wrong token nonce rejected');
$MockClaims=$Claims;
my$Accepted=$F->CallbackVerify(%Callback);ok($Accepted->{Success},'signed exact claims and flow are accepted');is($Accepted->{Data}->{TenantID},$T,'resolved tenant comes from trust route');
is($F->CallbackVerify(%Callback)->{Error},'FLOW_REPLAY','consumed callback cannot replay');
done_testing;
