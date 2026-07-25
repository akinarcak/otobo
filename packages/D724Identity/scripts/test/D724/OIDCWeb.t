# --
# Copyright (C) 2026 Data Market Bilgi Hizmetleri A.S.
# SPDX-License-Identifier: GPL-3.0-only
# --
use v5.24;
use strict;
use warnings;

use Test2::V0;
use Kernel::System::UnitTest::RegisterOM;

$Kernel::OM->ObjectParamAdd('Kernel::System::UnitTest::Helper'=>{RestoreDatabase=>1});
my $H=$Kernel::OM->Get('Kernel::System::UnitTest::Helper');
$H->ConfigSettingChange(Key=>'D724::Identity::Enabled',Value=>1);
$H->ConfigSettingChange(Key=>'D724::TenantGuard::Enabled',Value=>1);
$H->ConfigSettingChange(Key=>'D724::TenantGuard::AllowPlatformAdmin',Value=>1);
$H->ConfigSettingChange(Key=>'D724::Identity::OIDC::RedirectURI',Value=>{
    agent=>'https://esm.example.invalid/otobo/index.pl?Action=Login',
    customer=>'https://esm.example.invalid/otobo/customer.pl?Action=Login',
});

my$Suffix=lc$H->GetRandomID();my$Tenant="oidc-web-$Suffix";my$Issuer="https://login.example.invalid/$Suffix";my$Audience="client-$Suffix";
my$Directory=$Kernel::OM->Get('Kernel::System::D724::TenantDirectory');my$Identity=$Kernel::OM->Get('Kernel::System::D724::Identity');my$DB=$Kernel::OM->Get('Kernel::System::DB');
my$Platform={ID=>'platform',Roles=>['platform_admin'],TenantIDs=>['bootstrap']};
ok($Directory->TenantCreate(Subject=>$Platform,TenantID=>$Tenant,Name=>'OIDC Web',UserID=>1)->{Success},'tenant created');
my$Admin={ID=>'admin',TenantIDs=>[$Tenant],RoleBindings=>{$Tenant=>['tenant_admin']}};
ok($Directory->MembershipGrant(Subject=>$Admin,TenantID=>$Tenant,MemberUserID=>1,Role=>'tenant_admin',UserID=>1)->{Success},'preprovisioned agent has tenant membership');
ok($Identity->ProviderCreate(Subject=>$Admin,TenantID=>$Tenant,Key=>'workforce',Issuer=>$Issuer,Audience=>$Audience,AllowedDomains=>['localhost'],GroupRoleMap=>{agents=>'agent'},UserID=>1)->{Success},'trust route created');

my$YAML=$Kernel::OM->Get('Kernel::System::YAML');my$Name="careoncloud:$Tenant:workforce:agent";my$Secret='unit-secret';my$Redirect='https://esm.example.invalid/otobo/index.pl?Action=Login';my$Discovery="$Issuer/.well-known/openid-configuration";my$Valid=1;my$TTL=300;my$EmptyYAML=$YAML->Dump(Data=>{});
$DB->Do(SQL=>q{INSERT INTO oidc_profiles (name,client_id,client_secret,redirect_uri,openid_config,ssl_options,misc,ttl,create_time,create_by,change_time,change_by,valid_id) VALUES (?,?,?,?,?,?,?,?,current_timestamp,1,current_timestamp,1,?)},Bind=>[\$Name,\$Audience,\$Secret,\$Redirect,\$Discovery,\$EmptyYAML,\$EmptyYAML,\$TTL,\$Valid]);

my$Metadata={issuer=>$Issuer,authorization_endpoint=>"$Issuer/authorize",token_endpoint=>"$Issuer/token",jwks_uri=>"$Issuer/jwks",id_token_signing_alg_values_supported=>['RS256']};
my$OIDC=$Kernel::OM->Get('Kernel::System::OpenIDConnect');my$Configuration=$Kernel::OM->Get('Kernel::System::OpenIDConnect::Configuration');my$Token=$Kernel::OM->Get('Kernel::System::OpenIDConnect::Token');my$Web=$Kernel::OM->Get('Kernel::System::D724::OIDCWeb');
my$CapturedAuth;my$Claims;
no warnings 'redefine';
local *Kernel::System::OpenIDConnect::Configuration::GetProviderData=sub{return{OpenIDConfiguration=>$Metadata}};
local *Kernel::System::OpenIDConnect::BuildRedirectURL=sub{my($Self,%Param)=@_;$CapturedAuth=\%Param;return 'https://login.example.invalid/authorize?safe=1'};
local *Kernel::System::OpenIDConnect::RequestIDToken=sub{return'signed.jwt.value'};
local *Kernel::System::OpenIDConnect::Token::Validate=sub{return{Success=>1,TokenData=>$Claims}};

my$Start=$Web->Start(TenantID=>$Tenant,ProviderKey=>'workforce',Surface=>'agent',BrowserBinding=>'b'x43,ReturnPath=>'/otobo/index.pl?Action=AgentDashboard');ok($Start->{Success},'agent OIDC web flow starts');
is($Start->{Data}->{RedirectURL},'https://login.example.invalid/authorize?safe=1','only validated authorization URL is returned');
is($CapturedAuth->{AuthRequest}->{CodeChallengeMethod},'S256','web adapter requires PKCE S256');is($CapturedAuth->{ClientSettings}->{RedirectURI},$Redirect,'exact configured redirect URI is used');
like($Start->{Data}->{CookieName},qr/\AD724OIDC-[A-Za-z0-9_-]{20,128}\z/,'state-specific cookie name returned');unlike($Start->{Data}->{CookieValue},qr/$Secret/,'cookie never contains client secret');
is($Web->Start(TenantID=>$Tenant,ProviderKey=>'workforce',Surface=>'customer',BrowserBinding=>'b'x43,ReturnPath=>'/otobo/customer.pl?Action=CustomerDashboard')->{Error},'SSO_PROVIDER_UNAVAILABLE','surface cannot reuse another surface profile');

my($Browser,$Verifier)=split /\./,$Start->{Data}->{CookieValue},2;
$Claims={iss=>$Issuer,aud=>$Audience,sub=>'root-subject',preferred_username=>'root@localhost',email=>'root@localhost',groups=>['agents'],nonce=>$CapturedAuth->{AuthRequest}->{Nonce},exp=>time+300,iat=>time};
my$Done=$Web->Callback(Surface=>'agent',State=>$Start->{Data}->{State},Code=>'authorization-code',BrowserBinding=>$Browser,CodeVerifier=>$Verifier);ok($Done->{Success},'verified callback authenticates preprovisioned tenant agent');is($Done->{Data}->{Login},'root@localhost','callback returns exact preprovisioned login');is($Done->{Data}->{TenantID},$Tenant,'callback tenant comes from stored trust route');
is($Web->Callback(Surface=>'agent',State=>$Start->{Data}->{State},Code=>'authorization-code',BrowserBinding=>$Browser,CodeVerifier=>$Verifier)->{Error},'FLOW_NOT_FOUND_OR_EXPIRED','consumed flow cannot be used for a second token exchange');

done_testing;
