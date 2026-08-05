# --
# CareOnCloud ESM enterprise service management platform.
# SPDX-License-Identifier: GPL-3.0-only
# --
package Kernel::Modules::AgentCareOnCloudChange;
use v5.24;use strict;use warnings;
our $ObjectManagerDisabled=1;
sub new{my($Type,%P)=@_;return bless{%P},$Type}
sub Run{
 my($S,%P)=@_;my$L=$Kernel::OM->Get('Kernel::Output::HTML::Layout');my$W=$Kernel::OM->Get('Kernel::System::Web::Request');
 my$D=$Kernel::OM->Get('Kernel::System::CareOnCloud::TenantDirectory');my$G=$Kernel::OM->Get('Kernel::System::CareOnCloud::TenantGuard');my$C=$Kernel::OM->Get('Kernel::System::CareOnCloud::Change');
 my$Ctx=$D->ContextGet(UserID=>$S->{UserID});return$L->NoPermission(WithHeader=>'yes')if!$Ctx->{Success};my$Sub=$Ctx->{Subject};
 my@Tenants=grep{$G->DecisionGet(Subject=>$Sub,Resource=>{TenantID=>$_},Action=>'case.read')->{Allowed}}@{$Sub->{TenantIDs}};return$L->NoPermission(WithHeader=>'yes')if!@Tenants;
 my%Own=map{$_=>1}@Tenants;my$Tenant=$W->GetParam(Param=>'TenantID')//$Tenants[0];return$L->NoPermission(WithHeader=>'yes')if!$Own{$Tenant};
 my$Action=$S->{Subaction}//q{};if($Action){$L->ChallengeTokenCheck();my%X=(Subject=>$Sub,TenantID=>$Tenant,UserID=>$S->{UserID});my$R;
  if($Action eq'Create'){$R=$C->Create(%X,map{$_=>$W->GetParam(Param=>$_)}qw(Title Description ChangeType Impact Likelihood ImplementationPlan TestPlan BackoutPlan))}
  elsif($Action eq'Submit'){$R=$C->Submit(%X,ChangeID=>$W->GetParam(Param=>'ChangeID'),ExpectedVersion=>$W->GetParam(Param=>'ExpectedVersion'))}
  elsif($Action eq'Decide'){$R=$C->Decide(%X,ChangeID=>$W->GetParam(Param=>'ChangeID'),ExpectedVersion=>$W->GetParam(Param=>'ExpectedVersion'),Decision=>$W->GetParam(Param=>'Decision'),Comment=>$W->GetParam(Param=>'Comment'))}
  elsif($Action eq'Transition'){$R=$C->Transition(%X,ChangeID=>$W->GetParam(Param=>'ChangeID'),ExpectedVersion=>$W->GetParam(Param=>'ExpectedVersion'),ToStatus=>$W->GetParam(Param=>'ToStatus'))}
  else{$R={Success=>0,Error=>'ACTION_INVALID'}}
  return$L->Redirect(OP=>"Action=AgentCareOnCloudChange;TenantID=$Tenant")if$R->{Success};$P{Error}=$R->{Error};
 }
 for my$T(@Tenants){$L->Block(Name=>'TenantOption',Data=>{TenantID=>$T,Selected=>$T eq$Tenant?'selected':q{}})}
 my$CanManage=$G->DecisionGet(Subject=>$Sub,Resource=>{TenantID=>$Tenant},Action=>'case.delete')->{Allowed}?1:0;
 my$List=$C->List(Subject=>$Sub,TenantID=>$Tenant,UserID=>$S->{UserID});return$L->NoPermission(WithHeader=>'yes')if!$List->{Success};
 my%Count;for my$R(@{$List->{Data}}){$Count{$R->{Status}}++;$L->Block(Name=>'ChangeRow',Data=>$R);$L->Block(Name=>'SubmitAction',Data=>$R)if$R->{Status}eq'draft';$L->Block(Name=>'CABAction',Data=>$R)if$R->{Status}eq'awaiting_approval'&&$CanManage;$L->Block(Name=>'ScheduledAction',Data=>$R)if$R->{Status}eq'scheduled';$L->Block(Name=>'ImplementingAction',Data=>$R)if$R->{Status}eq'implementing'}
 my$O=$L->Header(Title=>'CareOnCloud Change Enablement');$O.=$L->NavigationBar();$O.=$L->Notify(Priority=>'Error',Info=>$P{Error})if$P{Error};
 $O.=$L->Output(TemplateFile=>'AgentCareOnCloudChange',Data=>{TenantID=>$Tenant,Total=>scalar@{$List->{Data}},Awaiting=>$Count{awaiting_approval}//0,Scheduled=>$Count{scheduled}//0,Implementing=>$Count{implementing}//0,CanManage=>$CanManage});$O.=$L->Footer();return$O;
}
1;
