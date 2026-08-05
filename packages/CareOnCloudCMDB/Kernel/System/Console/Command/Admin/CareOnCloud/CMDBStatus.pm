# --
# SPDX-License-Identifier: GPL-3.0-only
# --
package Kernel::System::Console::Command::Admin::CareOnCloud::CMDBStatus;
use v5.24;use strict;use warnings;
use parent qw(Kernel::System::Console::BaseCommand);
our @ObjectDependencies=('Kernel::Config','Kernel::System::DB','Kernel::System::JSON','Kernel::System::CareOnCloud::CMDBConstraint');
sub Configure{my($S)=@_;$S->Description('Validate the CareOnCloud tenant-safe CMDB repository.');$S->AddOption(Name=>'json',Description=>'Print machine-readable JSON output.',Required=>0,HasValue=>0);return}
sub Run{my($S)=@_;my$DB=$Kernel::OM->Get('Kernel::System::DB');my%E=map{$_=>1}$DB->ListTables();my%T=map{$_=>$E{$_}?1:0}qw(careoncloud_service_category careoncloud_service_category_service careoncloud_service_instance careoncloud_ci_type careoncloud_ci careoncloud_ci_relation careoncloud_service_instance_ci);my$Enabled=$Kernel::OM->Get('Kernel::Config')->Get('CareOnCloud::CMDB::Enabled')?1:0;my$C=$Kernel::OM->Get('Kernel::System::CareOnCloud::CMDBConstraint')->StatusGet();my$OK=$Enabled&&$C->{Success}&&!grep{!$T{$_}}keys%T;my$R={Success=>$OK?1:0,Enabled=>$Enabled,Package=>'CareOnCloudCMDB',Version=>'0.4.1',Tables=>\%T,TenantConstraints=>$C};if($S->GetOption('json')){$S->Print($Kernel::OM->Get('Kernel::System::JSON')->Encode(Data=>$R,SortKeys=>1,Pretty=>1))}else{$S->Print("CareOnCloud CMDB status\n");$S->Print('Repository: '.($Enabled?'enabled':'disabled')."\n");for my$N(sort keys%T){$S->Print("$N: ".($T{$N}?'OK':'MISSING')."\n")}$S->Print($OK?"Status: OK\n":"Status: FAILED\n")}return$OK?$S->ExitCodeOk():$S->ExitCodeError()}
1;
