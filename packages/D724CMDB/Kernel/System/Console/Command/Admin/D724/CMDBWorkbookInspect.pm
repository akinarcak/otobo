# --
# SPDX-License-Identifier: GPL-3.0-only
# --
package Kernel::System::Console::Command::Admin::D724::CMDBWorkbookInspect;
use v5.24;use strict;use warnings;use parent qw(Kernel::System::Console::BaseCommand);
our @ObjectDependencies=('Kernel::System::D724::CMDBWorkbook','Kernel::System::JSON');
sub Configure{my($S)=@_;$S->Description('Validate and preview a CareOnCloud 4me catalog workbook without changing data.');$S->AddOption(Name=>'file',Description=>'Absolute path to an XLSX workbook.',Required=>1,HasValue=>1,ValueRegex=>qr{\A/.+\.xlsx\z});$S->AddOption(Name=>'include-rows',Description=>'Include normalized mapping rows in JSON.',Required=>0,HasValue=>0);return}
sub Run{my($S)=@_;my$R=$Kernel::OM->Get('Kernel::System::D724::CMDBWorkbook')->Inspect(Path=>$S->GetOption('file'),IncludeRows=>$S->GetOption('include-rows')?1:0);$S->Print($Kernel::OM->Get('Kernel::System::JSON')->Encode(Data=>$R,SortKeys=>1,Pretty=>1));return$R->{Success}?$S->ExitCodeOk():$S->ExitCodeError()}
1;
