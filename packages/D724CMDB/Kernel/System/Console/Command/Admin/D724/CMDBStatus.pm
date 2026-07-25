# --
# SPDX-License-Identifier: GPL-3.0-only
# --
package Kernel::System::Console::Command::Admin::D724::CMDBStatus;
use v5.24;use strict;use warnings;
use parent qw(Kernel::System::Console::BaseCommand);
our @ObjectDependencies=('Kernel::Config','Kernel::System::DB','Kernel::System::JSON','Kernel::System::D724::CMDBConstraint');
sub Configure{my($S)=@_;$S->Description('Validate the CareOnCloud tenant-safe CMDB repository.');$S->AddOption(Name=>'json',Description=>'Print machine-readable JSON output.',Required=>0,HasValue=>0);return}
sub Run{my($S)=@_;my$DB=$Kernel::OM->Get('Kernel::System::DB');my%E=map{$_=>1}$DB->ListTables();my%T=map{$_=>$E{$_}?1:0}qw(d724_service_category d724_service_category_service d724_service_instance d724_ci_type d724_ci d724_ci_relation d724_service_instance_ci);my$Enabled=$Kernel::OM->Get('Kernel::Config')->Get('D724::CMDB::Enabled')?1:0;my$C=$Kernel::OM->Get('Kernel::System::D724::CMDBConstraint')->StatusGet();my$OK=$Enabled&&$C->{Success}&&!grep{!$T{$_}}keys%T;my$R={Success=>$OK?1:0,Enabled=>$Enabled,Package=>'D724CMDB',Version=>'0.3.4',Tables=>\%T,TenantConstraints=>$C};if($S->GetOption('json')){$S->Print($Kernel::OM->Get('Kernel::System::JSON')->Encode(Data=>$R,SortKeys=>1,Pretty=>1))}else{$S->Print("CareOnCloud CMDB status\n");$S->Print('Repository: '.($Enabled?'enabled':'disabled')."\n");for my$N(sort keys%T){$S->Print("$N: ".($T{$N}?'OK':'MISSING')."\n")}$S->Print($OK?"Status: OK\n":"Status: FAILED\n")}return$OK?$S->ExitCodeOk():$S->ExitCodeError()}
1;
