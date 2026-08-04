# --
# Copyright (C) 2026 Data Market Bilgi Hizmetleri A.S.
# SPDX-License-Identifier: GPL-3.0-only
# --
use v5.24;
use strict;
use warnings;

use Test2::V0;
use HTTP::Request::Common qw(GET);
use Kernel::System::UnitTest::RegisterOM;

$Kernel::OM->ObjectParamAdd('Kernel::System::UnitTest::Helper'=>{RestoreDatabase=>1});
my$H=$Kernel::OM->Get('Kernel::System::UnitTest::Helper');$H->ConfigSettingChange(Key=>'CheckEmailAddresses',Value=>0);my$Suffix=lc$H->GetRandomID();my$Login="oidc-password-$Suffix";my$Password='Unit-Test-Password-2026!';
my$UserID=$Kernel::OM->Get('Kernel::System::User')->UserAdd(UserFirstname=>'OIDC',UserLastname=>'Fallback',UserLogin=>$Login,UserPw=>$Password,UserEmail=>"$Login\@localhost",ValidID=>1,ChangeUserID=>1);ok($UserID,'password fallback fixture agent created');

sub RequestSet{my($URL,$Cookie)=@_;$Kernel::OM->ObjectsDiscard(Objects=>['Kernel::System::Web::Request','Kernel::Output::HTML::Layout']);my$HTTP=GET($URL);$HTTP->header(Cookie=>$Cookie)if$Cookie;$Kernel::OM->ObjectParamAdd('Kernel::System::Web::Request'=>{HTTPRequest=>$HTTP});}

RequestSet('https://esm.example.invalid/careoncloud/index.pl');
require Kernel::System::Auth::CareOnCloudOpenIDConnect;require Kernel::System::CustomerAuth::CareOnCloudOpenIDConnect;
my$Agent=Kernel::System::Auth::CareOnCloudOpenIDConnect->new(Count=>'');
is($Agent->GetOption(What=>'PreAuth'),0,'normal login does not activate pre-auth redirect');is($Agent->Auth(User=>$Login,Pw=>$Password),$Login,'existing DB password agent login still works');

my$State='s'x43;my$Verifier='v'x64;my$Browser='b'x43;my$StartSurface;my$CallbackSurface;
$Kernel::OM->Get('Kernel::System::CareOnCloud::OIDCWeb');
no warnings 'redefine';
local *Kernel::System::CareOnCloud::OIDCWeb::Start=sub{my($Self,%Param)=@_;$StartSurface=$Param{Surface};return{Success=>1,Data=>{RedirectURL=>'https://login.example.invalid/authorize',CookieName=>"CareOnCloudOIDC-$State",CookieValue=>"$Browser.$Verifier",CookieTTL=>300}}};
local *Kernel::System::CareOnCloud::OIDCWeb::Callback=sub{my($Self,%Param)=@_;$CallbackSurface=$Param{Surface};return{Success=>1,Data=>{Login=>$Login,TenantID=>'tenant-a',ReturnPath=>'/careoncloud/index.pl?Action=AgentDashboard'}}};

RequestSet('https://esm.example.invalid/careoncloud/index.pl?CareOnCloudSSO=1&TenantID=tenant-a&ProviderKey=workforce');
is($Agent->GetOption(What=>'PreAuth'),1,'explicit tenant/provider selection activates SSO pre-auth');my$Pre=$Agent->PreAuth();is($Pre->{RedirectURL},'https://login.example.invalid/authorize','pre-auth returns provider redirect');is($StartSurface,'agent','agent backend binds agent surface');
my$Cookies=$Kernel::OM->Get('Kernel::Output::HTML::Layout')->{SetCookies};is($Cookies->{"CareOnCloudOIDC-$State"}->{httponly},1,'flow cookie is HttpOnly');is($Cookies->{"CareOnCloudOIDC-$State"}->{secure},1,'flow cookie is Secure');is($Cookies->{"CareOnCloudOIDC-$State"}->{samesite},'lax','flow cookie is SameSite Lax');

RequestSet("https://esm.example.invalid/careoncloud/index.pl?Action=Login&state=$State&code=authorization-code","CareOnCloudOIDC-$State=$Browser.$Verifier");
is($Agent->Auth(),$Login,'agent callback returns verified login');is($CallbackSurface,'agent','callback is bound to agent surface');is($Agent->PostAuth()->{RequestedURL},'Action=AgentDashboard','post-auth uses verified local return action');

RequestSet("https://esm.example.invalid/careoncloud/customer.pl?CareOnCloudSSO=1&TenantID=tenant-a&ProviderKey=workforce");
my$Customer=Kernel::System::CustomerAuth::CareOnCloudOpenIDConnect->new(Count=>'');is($Customer->GetOption(What=>'PreAuth'),1,'customer backend recognizes explicit SSO selection');$Customer->PreAuth();is($StartSurface,'customer','customer backend binds customer surface');

done_testing;
