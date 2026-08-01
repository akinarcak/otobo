# --
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
my $API = $Kernel::OM->Get('Kernel::System::D724::APIAuth');
my $SCIM = $Kernel::OM->Get('Kernel::System::D724::SCIM');
my $Suffix = lc $Helper->GetRandomID();
my $TenantA = "scim-a-$Suffix";
my $TenantB = "scim-b-$Suffix";

for my $Setting (
    [ 'D724::SCIM::Enabled', 1 ], [ 'D724::API::Enabled', 1 ], [ 'D724::API::BcryptCost', 9 ],
    [ 'D724::API::TokenTTLMax', 900 ], [ 'D724::API::RateLimitMax', 200 ],
    [ 'D724::Audit::Enabled', 1 ], [ 'D724::TenantGuard::Enabled', 1 ],
    [ 'CheckEmailAddresses', 0 ],
) { $Helper->ConfigSettingChange( Key => $Setting->[0], Value => $Setting->[1] ) }

for my $T ($TenantA,$TenantB) {
    my @V=($T,"SCIM $T",1,1);my @B=map{\$_}@V;
    ok($DB->Do(SQL=>"INSERT INTO d724_tenant (key_name,name,status,version,create_time,create_by,change_time,change_by) VALUES (?,?,'active',1,current_timestamp,?,current_timestamp,?)",Bind=>\@B),"tenant $T created");
}
my $Company=$Kernel::OM->Get('Kernel::System::CustomerCompany')->CustomerCompanyAdd(CustomerID=>$TenantA,CustomerCompanyName=>"SCIM Company $Suffix",CustomerCompanyStreet=>'Test',CustomerCompanyZIP=>'34000',CustomerCompanyCity=>'Istanbul',CustomerCompanyCountry=>'TR',ValidID=>1,UserID=>1);
ok($Company,'customer company fixture created');

my $Admin={ID=>'scim-admin',TenantIDs=>[$TenantA],RoleBindings=>{$TenantA=>['tenant_admin']}};
my $Client=$API->ClientCreate(Subject=>$Admin,TenantID=>$TenantA,Name=>'SCIM Acceptance',Role=>'tenant_admin',UserID=>1,TokenTTL=>300,RateLimit=>200,ClientID=>"scim-$Suffix");
ok($Client->{Success},'tenant admin creates SCIM integration client');
my $Issued=$API->TokenIssue(ClientID=>$Client->{Data}->{ClientID},ClientSecret=>$Client->{Data}->{ClientSecret});ok($Issued->{Success},'tenant-bound bearer token issued');my $Token=$Issued->{Data}->{AccessToken};
my %Base=(AccessToken=>$Token,TenantID=>$TenantA);

my $Agent=$SCIM->UserCreate(%Base,ExternalID=>"entra-agent-$Suffix",Surface=>'agent',UserName=>"scim.agent.$Suffix",Email=>"scim.agent.$Suffix\@example.com",GivenName=>'SCIM',FamilyName=>'Agent',Active=>1);
diag "agent create error: ".($Agent->{Error}//'unknown') if !$Agent->{Success};
ok($Agent->{Success},'agent user provisioned');like($Agent->{Data}->{id},qr{\A[a-f0-9]{32}\z},'opaque SCIM id returned');is($Agent->{Data}->{meta}->{version},'W/"1"','user starts at weak ETag version 1');
my $AgentID=$Agent->{Data}->{id};
is($SCIM->UserGet(AccessToken=>$Token,TenantID=>$TenantB,SCIMID=>$AgentID)->{Error},'CROSS_TENANT','token cannot read another tenant');
is($SCIM->UserGet(%Base,SCIMID=>'f'x32)->{Error},'NOT_FOUND','unknown tenant-local id is hidden');
my $Filtered=$SCIM->UserList(%Base,FilterAttribute=>'userName',FilterOperator=>'eq',FilterValue=>"scim.agent.$Suffix",Count=>10);is($Filtered->{Data}->{totalResults},1,'bounded username filter finds exact user');
is($SCIM->UserList(%Base,FilterAttribute=>'emails',FilterOperator=>'co',FilterValue=>'example')->{Error},'FILTER_UNSUPPORTED','unbounded filter fails closed');
is($SCIM->UserReplace(%Base,SCIMID=>$AgentID,ExpectedVersion=>1,UserName=>'takeover',Email=>"new.$Suffix\@example.com",GivenName=>'New',FamilyName=>'Name',Surface=>'agent')->{Error},'IMMUTABLE_ATTRIBUTE','userName takeover is rejected');

my $Group=$SCIM->GroupCreate(%Base,ExternalID=>"entra-group-$Suffix",DisplayName=>"SCIM Agents $Suffix",Role=>'agent',Members=>[$AgentID]);
diag "group create error: ".($Group->{Error}//'unknown') if !$Group->{Success};
ok($Group->{Success},'SCIM group provisioned and reconciled');my $GroupID=$Group->{Data}->{id};is($Group->{Data}->{members}->[0]->{value},$AgentID,'group returns exact member');
$DB->Prepare(SQL=>"SELECT status FROM d724_tenant_agent_role r INNER JOIN d724_scim_user u ON u.native_user_id=r.user_id WHERE u.scim_id=? AND r.tenant_id=? AND r.role_name='agent'",Bind=>[\$AgentID,\$TenantA],Limit=>1);my($AgentRole)=$DB->FetchrowArray();is($AgentRole,'active','group membership grants tenant agent role');

my $Deactivated=$SCIM->UserReplace(%Base,SCIMID=>$AgentID,ExpectedVersion=>1,Email=>"new.$Suffix\@example.com",GivenName=>'New',FamilyName=>'Name',Surface=>'agent',Active=>0);
ok($Deactivated->{Success},'user deprovision succeeds');is($Deactivated->{Data}->{active},0,'SCIM resource is inactive');
$DB->Prepare(SQL=>"SELECT COUNT(*) FROM d724_tenant_agent_role r INNER JOIN d724_scim_user u ON u.native_user_id=r.user_id WHERE u.scim_id=? AND r.tenant_id=? AND r.status='active'",Bind=>[\$AgentID,\$TenantA]);my($ActiveRoles)=$DB->FetchrowArray();is($ActiveRoles,0,'deprovision revokes every role in the tenant');
my $Reactivated=$SCIM->UserReplace(%Base,SCIMID=>$AgentID,ExpectedVersion=>2,Email=>"new.$Suffix\@example.com",GivenName=>'New',FamilyName=>'Name',Surface=>'agent',Active=>1);ok($Reactivated->{Success},'reactivation succeeds');
$DB->Prepare(SQL=>"SELECT COUNT(*) FROM d724_tenant_agent_role r INNER JOIN d724_scim_user u ON u.native_user_id=r.user_id WHERE u.scim_id=? AND r.tenant_id=? AND r.status='active'",Bind=>[\$AgentID,\$TenantA]);($ActiveRoles)=$DB->FetchrowArray();is($ActiveRoles,2,'reactivation restores baseline and group-derived roles');

my $Customer=$SCIM->UserCreate(%Base,ExternalID=>"entra-customer-$Suffix",Surface=>'customer',UserName=>"scim.customer.$Suffix",Email=>"scim.customer.$Suffix\@example.com",GivenName=>'SCIM',FamilyName=>'Customer',Active=>1);
diag "customer create error: ".($Customer->{Error}//'unknown') if !$Customer->{Success};
ok($Customer->{Success},'customer portal user provisioned against tenant company');is($Customer->{Data}->{'urn:careoncloud:params:scim:schemas:extension:esm:2.0:User'}->{surface},'customer','customer surface is explicit');
is($SCIM->UserDelete(%Base,SCIMID=>$Customer->{Data}->{id},ExpectedVersion=>99)->{Error},'VERSION_CONFLICT','stale user DELETE is rejected');
ok($SCIM->UserDelete(%Base,SCIMID=>$Customer->{Data}->{id},ExpectedVersion=>1)->{Success},'user DELETE performs version-checked deprovision');

is($SCIM->GroupReplace(%Base,SCIMID=>$GroupID,ExpectedVersion=>99,DisplayName=>"SCIM Agents $Suffix",Role=>'agent',Members=>[])->{Error},'VERSION_CONFLICT','stale group write is rejected');
ok($SCIM->GroupDelete(%Base,SCIMID=>$GroupID,ExpectedVersion=>1)->{Success},'group deletion reconciles memberships');
is($SCIM->GroupGet(%Base,SCIMID=>$GroupID)->{Error},'NOT_FOUND','deleted group is gone');

my $Audit=$Kernel::OM->Get('Kernel::System::D724::Audit')->List(Subject=>$Admin,TenantID=>$TenantA,Limit=>100);
ok($Audit->{Success},'SCIM audit chain readable');ok(grep($_->{Action} eq 'scim.user.created',@{$Audit->{Data}}),'user creation has audit evidence');ok(grep($_->{ActorType} eq 'integration'&&$_->{ActorID} eq 'integration:'.$Client->{Data}->{ClientID},@{$Audit->{Data}}),'SCIM audit actor is the integration client');

# These APIs intentionally commit real transactions, so remove all acceptance
# fixtures explicitly instead of relying on the unit-test rollback wrapper.
$DB->Prepare(SQL=>'SELECT native_user_id FROM d724_scim_user WHERE tenant_id=? AND scim_id=?',Bind=>[\$TenantA,\$AgentID],Limit=>1);my($NativeAgentID)=$DB->FetchrowArray();
my $CustomerLogin="scim.customer.$Suffix";my $ClientID=$Client->{Data}->{ClientID};
for my $Delete (
    [ 'DELETE FROM d724_scim_group_member WHERE tenant_id=?', [\$TenantA] ],
    [ 'DELETE FROM d724_scim_group WHERE tenant_id=?', [\$TenantA] ],
    [ 'DELETE FROM d724_tenant_agent_role WHERE tenant_id=?', [\$TenantA] ],
    [ 'DELETE FROM d724_scim_user WHERE tenant_id=?', [\$TenantA] ],
    [ 'DELETE FROM d724_api_rate WHERE client_id=?', [\$ClientID] ],
    [ 'DELETE FROM d724_api_token WHERE client_id=?', [\$ClientID] ],
    [ 'DELETE FROM d724_api_client WHERE client_id=?', [\$ClientID] ],
    [ 'DELETE FROM d724_audit_event WHERE tenant_id=?', [\$TenantA] ],
    [ 'DELETE FROM d724_audit_head WHERE tenant_id=?', [\$TenantA] ],
) { ok($DB->Do(SQL=>$Delete->[0],Bind=>$Delete->[1]),'acceptance fixture removed') }
if($NativeAgentID){$DB->Do(SQL=>'DELETE FROM user_preferences WHERE user_id=?',Bind=>[\$NativeAgentID]);$DB->Do(SQL=>'DELETE FROM group_user WHERE user_id=?',Bind=>[\$NativeAgentID]);$DB->Do(SQL=>'DELETE FROM role_user WHERE user_id=?',Bind=>[\$NativeAgentID]);$DB->Do(SQL=>'DELETE FROM users WHERE id=?',Bind=>[\$NativeAgentID])}
$DB->Do(SQL=>'DELETE FROM customer_preferences WHERE user_id=?',Bind=>[\$CustomerLogin]);$DB->Do(SQL=>'DELETE FROM customer_user WHERE login=?',Bind=>[\$CustomerLogin]);$DB->Do(SQL=>'DELETE FROM customer_company WHERE customer_id=?',Bind=>[\$TenantA]);
for my $T($TenantA,$TenantB){$DB->Do(SQL=>'DELETE FROM d724_audit_event WHERE tenant_id=?',Bind=>[\$T]);$DB->Do(SQL=>'DELETE FROM d724_audit_head WHERE tenant_id=?',Bind=>[\$T]);ok($DB->Do(SQL=>'DELETE FROM d724_tenant WHERE key_name=?',Bind=>[\$T]),"tenant fixture $T removed")}

done_testing();
