# --
# Copyright (C) 2026 Data Market Bilgi Hizmetleri A.S.
# SPDX-License-Identifier: GPL-3.0-only
# --
package Kernel::System::Console::Command::Admin::D724::AuditStatus;
use v5.24; use strict; use warnings; use parent qw(Kernel::System::Console::BaseCommand);
our @ObjectDependencies = ('Kernel::System::DB','Kernel::System::JSON');
sub Configure { my ($Self)=@_; $Self->Description('Validate the D724 audit schema and print operational counts.'); $Self->AddOption(Name=>'json',Description=>'Print JSON.',Required=>0,HasValue=>0); return }
sub Run {
    my ($Self)=@_; my $DB=$Kernel::OM->Get('Kernel::System::DB'); my %E=map {$_=>1} $DB->ListTables();
    my %T=map {$_=>$E{$_}?1:0} qw(d724_audit_head d724_audit_event); my %C=(Tenants=>0,Events=>0);
    if($T{d724_audit_head}){$DB->Prepare(SQL=>'SELECT COUNT(*) FROM d724_audit_head');($C{Tenants})=$DB->FetchrowArray()}
    if($T{d724_audit_event}){$DB->Prepare(SQL=>'SELECT COUNT(*) FROM d724_audit_event');($C{Events})=$DB->FetchrowArray()}
    my $OK=!(grep{!$_}values %T); my $S={Success=>$OK?1:0,Package=>'D724Audit',Version=>'0.1.0',Tables=>\%T,Counts=>\%C};
    $Self->Print($Self->GetOption('json')?$Kernel::OM->Get('Kernel::System::JSON')->Encode(Data=>$S,SortKeys=>1,Pretty=>1):"D724 audit status\nEvents: $C{Events}\nStatus: ".($OK?'OK':'FAILED')."\n");
    return $OK?$Self->ExitCodeOk():$Self->ExitCodeError();
}
1;
