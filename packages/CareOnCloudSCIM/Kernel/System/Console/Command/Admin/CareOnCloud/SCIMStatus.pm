# --
# SPDX-License-Identifier: GPL-3.0-only
# --
package Kernel::System::Console::Command::Admin::CareOnCloud::SCIMStatus;
use v5.24; use strict; use warnings;
use parent qw(Kernel::System::Console::BaseCommand);
our @ObjectDependencies = qw(Kernel::Config Kernel::System::CareOnCloud::SCIMBrandMigration Kernel::System::DB Kernel::System::JSON Kernel::System::Main);
sub Configure { $_[0]->Description('Validate CareOnCloud tenant-isolated SCIM 2.0 provisioning.'); $_[0]->AddOption(Name=>'json',Description=>'Print JSON.',Required=>0,HasValue=>0); return }
sub Run {
    my($Self)=@_;my$DB=$Kernel::OM->Get('Kernel::System::DB');my%Have=map{$_=>1}$DB->ListTables();my%Tables=map{$_=>($Have{$_}?1:0)}qw(careoncloud_scim_user careoncloud_scim_group careoncloud_scim_group_member careoncloud_api_client careoncloud_api_token careoncloud_tenant);
    my$Enabled=$Kernel::OM->Get('Kernel::Config')->Get('CareOnCloud::SCIM::Enabled')?1:0;my$Home=$Kernel::OM->Get('Kernel::Config')->Get('Home');my$PSGI=$Kernel::OM->Get('Kernel::System::Main')->FileRead(Location=>"$Home/bin/psgi-bin/careoncloud.psgi",Mode=>'utf8',Result=>'SCALAR');my$Mount=$PSGI&&${$PSGI}=~m{mount[ ]+'/scim/v2'}smx?1:0;my$BrandSchema=$Kernel::OM->Get('Kernel::System::CareOnCloud::SCIMBrandMigration')->StatusGet();
    my%Counts;for my$Spec([Users=>'careoncloud_scim_user'],[Groups=>'careoncloud_scim_group'],[Memberships=>'careoncloud_scim_group_member']){next if!$Tables{$Spec->[1]};$DB->Prepare(SQL=>'SELECT COUNT(*) FROM '.$Spec->[1]);($Counts{$Spec->[0]})=$DB->FetchrowArray();$Counts{$Spec->[0]}//=0}
    my$Success=$Enabled&&$Mount&&$BrandSchema->{Success}&&!grep{!$Tables{$_}}keys%Tables;my$Data={Success=>$Success?1:0,Enabled=>$Enabled,CanonicalMount=>$Mount,BrandSchema=>$BrandSchema,Package=>'CareOnCloudSCIM',Version=>'0.2.0',PolicyAction=>'scim.provision',Tables=>\%Tables,Counts=>\%Counts};
    if($Self->GetOption('json')){$Self->Print($Kernel::OM->Get('Kernel::System::JSON')->Encode(Data=>$Data,SortKeys=>1,Pretty=>1))}else{$Self->Print('CareOnCloud SCIM 2.0: '.($Success?'OK':'FAILED')."\n")}
    return$Success?$Self->ExitCodeOk():$Self->ExitCodeError();
}
1;
