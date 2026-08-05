# --
# SPDX-License-Identifier: GPL-3.0-only
# --
package Kernel::System::Console::Command::Admin::CareOnCloud::CMDBWorkbookImport;
use v5.24;use strict;use warnings;use parent qw(Kernel::System::Console::BaseCommand);
our @ObjectDependencies=('Kernel::Config','Kernel::System::CareOnCloud::CMDBWorkbookImport','Kernel::System::JSON');
sub Configure{my($S)=@_;$S->Description('Import a validated workbook into explicitly labelled demo tenants.');$S->AddOption(Name=>'file',Description=>'Absolute XLSX path.',Required=>1,HasValue=>1,ValueRegex=>qr{\A/.+\.xlsx\z});$S->AddOption(Name=>'actor-user-id',Description=>'Existing CareOnCloud agent user ID.',Required=>1,HasValue=>1,ValueRegex=>qr{\A[1-9][0-9]*\z});$S->AddOption(Name=>'demo-data',Description=>'Acknowledge that company names are demo/reference data.',Required=>1,HasValue=>0);$S->AddOption(Name=>'confirm',Description=>'Apply changes. Without this flag the command fails closed.',Required=>1,HasValue=>0);return}
sub Run{my($S)=@_;my$U=0+$S->GetOption('actor-user-id');my$Config=$Kernel::OM->Get('Kernel::Config');local$Config->{'CareOnCloud::TenantGuard::AllowPlatformAdmin'}=1;my$R=$Kernel::OM->Get('Kernel::System::CareOnCloud::CMDBWorkbookImport')->Apply(Path=>$S->GetOption('file'),UserID=>$U,Confirm=>$S->GetOption('confirm')?1:0,DemoData=>$S->GetOption('demo-data')?1:0,Subject=>{ID=>"workbook-import:$U",Roles=>['platform_admin'],TenantIDs=>['bootstrap']});$S->Print($Kernel::OM->Get('Kernel::System::JSON')->Encode(Data=>$R,SortKeys=>1,Pretty=>1));return$R->{Success}?$S->ExitCodeOk():$S->ExitCodeError()}
1;
