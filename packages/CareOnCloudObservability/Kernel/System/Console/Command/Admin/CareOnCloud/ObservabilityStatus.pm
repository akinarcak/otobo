# --
# Copyright (C) 2026 Data Market Bilgi Hizmetleri A.S.
# SPDX-License-Identifier: GPL-3.0-only
# --
package Kernel::System::Console::Command::Admin::CareOnCloud::ObservabilityStatus;
use v5.24; use strict; use warnings;
use parent qw(Kernel::System::Console::BaseCommand);
our @ObjectDependencies = ('Kernel::System::CareOnCloud::Observability', 'Kernel::System::JSON');
sub Configure {
    my ($Self)=@_; $Self->Description('Print consolidated CareOnCloud observability health.');
    $Self->AddOption(Name=>'json',Description=>'Print JSON.',Required=>0,HasValue=>0);
    $Self->AddOption(Name=>'prometheus',Description=>'Print Prometheus exposition.',Required=>0,HasValue=>0); return;
}
sub Run {
    my ($Self)=@_; my $Service=$Kernel::OM->Get('Kernel::System::CareOnCloud::Observability'); my $Status=$Service->StatusData();
    if ($Self->GetOption('prometheus')) { $Self->Print($Service->PrometheusRender(Status=>$Status)) }
    elsif ($Self->GetOption('json')) { $Self->Print($Kernel::OM->Get('Kernel::System::JSON')->Encode(Data=>$Status,SortKeys=>1,Pretty=>1)."\n") }
    else { $Self->Print('CareOnCloud observability status: '.($Status->{Success}?'OK':'FAILED')."\n") }
    return $Status->{Success} ? $Self->ExitCodeOk() : $Self->ExitCodeError();
}
1;
