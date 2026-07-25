# --
# Copyright (C) 2026 Data Market Bilgi Hizmetleri A.S.
# SPDX-License-Identifier: GPL-3.0-only
# --
package Kernel::System::Console::Command::Admin::D724::IdentityStatus;
use v5.24; use strict; use warnings;
use parent qw(Kernel::System::Console::BaseCommand);
our @ObjectDependencies = qw(Kernel::Config Kernel::System::DB Kernel::System::JSON);
sub Configure { $_[0]->Description('Validate the CareOnCloud federated identity trust boundary.'); $_[0]->AddOption(Name=>'json',Description=>'Print JSON.',Required=>0,HasValue=>0); return }
sub Run {
    my ($Self)=@_; my $DB=$Kernel::OM->Get('Kernel::System::DB'); my %T=map {$_=>1} $DB->ListTables();
    my %Tables=map {$_=>($T{$_}?1:0)} qw(d724_identity_provider d724_federated_identity);
    my $Enabled=$Kernel::OM->Get('Kernel::Config')->Get('D724::Identity::Enabled')?1:0;
    my $Success=$Enabled && !grep {!$Tables{$_}} keys %Tables;
    my $Data={Success=>$Success?1:0,Enabled=>$Enabled,Package=>'D724Identity',Version=>'0.1.1',Tables=>\%Tables};
    if($Self->GetOption('json')){$Self->Print($Kernel::OM->Get('Kernel::System::JSON')->Encode(Data=>$Data,SortKeys=>1,Pretty=>1))}
    else{$Self->Print('CareOnCloud identity: '.($Success?'OK':'FAILED')."\n")}
    return $Success?$Self->ExitCodeOk():$Self->ExitCodeError();
}
1;
