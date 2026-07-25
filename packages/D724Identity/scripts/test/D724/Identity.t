# --
# Copyright (C) 2026 Data Market Bilgi Hizmetleri A.S.
# SPDX-License-Identifier: GPL-3.0-only
# --
use v5.24; use strict; use warnings; use utf8;
use Test2::V0;
use Kernel::System::UnitTest::RegisterOM;
$Kernel::OM->ObjectParamAdd('Kernel::System::UnitTest::Helper'=>{RestoreDatabase=>1});
my $Helper=$Kernel::OM->Get('Kernel::System::UnitTest::Helper');
$Helper->ConfigSettingChange(Key=>'D724::Identity::Enabled',Value=>1);
$Helper->ConfigSettingChange(Key=>'D724::TenantGuard::Enabled',Value=>1);
$Helper->ConfigSettingChange(Key=>'D724::TenantGuard::AllowPlatformAdmin',Value=>1);
my $Directory=$Kernel::OM->Get('Kernel::System::D724::TenantDirectory');
my $Identity=$Kernel::OM->Get('Kernel::System::D724::Identity');
my $Suffix=lc $Helper->GetRandomID(); my ($A,$B)=("identity-a-$Suffix","identity-b-$Suffix");
my $Platform={ID=>'identity-platform',Roles=>['platform_admin'],TenantIDs=>['bootstrap']};
ok($Directory->TenantCreate(Subject=>$Platform,TenantID=>$A,Name=>'Identity A',UserID=>1)->{Success},'tenant A created');
ok($Directory->TenantCreate(Subject=>$Platform,TenantID=>$B,Name=>'Identity B',UserID=>1)->{Success},'tenant B created');
my $AdminA={ID=>'identity-admin-a',TenantIDs=>[$A],RoleBindings=>{$A=>['tenant_admin']}};
my $AdminB={ID=>'identity-admin-b',TenantIDs=>[$B],RoleBindings=>{$B=>['tenant_admin']}};
my $Issuer="https://login.example.invalid/$Suffix"; my $Audience="careoncloud-$Suffix";
my $Provider=$Identity->ProviderCreate(Subject=>$AdminA,TenantID=>$A,Key=>'corporate-oidc',Issuer=>$Issuer,Audience=>$Audience,
    AllowedDomains=>['example.com'],GroupRoleMap=>{'esm-agents'=>'agent','esm-auditors'=>'auditor'},UserID=>1);
ok($Provider->{Success},'tenant admin creates an exact issuer/audience trust route');
is($Identity->ProviderCreate(Subject=>$AdminB,TenantID=>$A,Key=>'cross',Issuer=>'https://other.invalid',Audience=>'other',AllowedDomains=>['example.com'],GroupRoleMap=>{},UserID=>1)->{Error},'FORBIDDEN','other tenant cannot configure provider');
is($Identity->ProviderCreate(Subject=>$AdminB,TenantID=>$B,Key=>'duplicate-route',Issuer=>$Issuer,Audience=>$Audience,AllowedDomains=>['example.com'],GroupRoleMap=>{},UserID=>1)->{Error},'PROVIDER_ROUTE_EXISTS','issuer and audience route to only one tenant');
my $Base={Verifier=>'oidc',Verified=>1,Issuer=>$Issuer,Audience=>$Audience,Claims=>{sub=>'subject-1',preferred_username=>'Ada.User',email=>'ada.user@example.com',groups=>['esm-agents'],tenant_id=>$B}};
is($Identity->VerifiedClaimsResolve(Verification=>{%{$Base},Verified=>0})->{Error},'VERIFICATION_REQUIRED','unverified claims are rejected');
is($Identity->VerifiedClaimsResolve(Verification=>{%{$Base},Issuer=>'https://evil.invalid'})->{Error},'TRUST_ROUTE_NOT_FOUND','unregistered issuer is rejected');
my $Resolved=$Identity->VerifiedClaimsResolve(Verification=>$Base);
diag( 'resolve error=' . ( $Resolved->{Error} // 'unknown' ) . ' reason=' . ( $Resolved->{Reason} // q{} ) ) if !$Resolved->{Success};
ok($Resolved->{Success},'verified exact trust route resolves');
is($Resolved->{Data}->{TenantID},$A,'tenant comes from provider route, not token tenant claim');
ok($Resolved->{Data}->{TenantClaimIgnored},'untrusted tenant claim is explicitly ignored');
is($Resolved->{Data}->{Roles},[qw(agent requester)],'only allow-listed groups become tenant roles');
is($Identity->VerifiedClaimsResolve(Verification=>{%{$Base},Claims=>{%{$Base->{Claims}},email=>'ada@evil.example'}})->{Error},'EMAIL_DOMAIN_DENIED','email domain allow-list is enforced');
my $Replay=$Identity->VerifiedClaimsResolve(Verification=>$Base);
is($Replay->{Data}->{IdentityID},$Resolved->{Data}->{IdentityID},'subject mapping is stable and idempotent');
is($Identity->VerifiedClaimsResolve(Verification=>{%{$Base},Claims=>{%{$Base->{Claims}},preferred_username=>'changed.user'}})->{Error},'SUBJECT_LOGIN_CONFLICT','subject cannot be rebound to another login');
my $Spoof={%{$Base},Claims=>{%{$Base->{Claims}},sub=>'subject-2',preferred_username=>'ada.user'}};
is($Identity->VerifiedClaimsResolve(Verification=>$Spoof)->{Error},'LOGIN_ALREADY_LINKED','one tenant login cannot be linked to a second subject');
done_testing;
