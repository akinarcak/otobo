# --
# Copyright (C) 2026 Data Market Bilgi Hizmetleri A.S.
# SPDX-License-Identifier: GPL-3.0-only
# --
package Kernel::System::Console::Command::Admin::D724::APIStatus;
use v5.24; use strict; use warnings; use parent qw(Kernel::System::Console::BaseCommand);
our $VERSION = '0.1.2'; our @ObjectDependencies = ('Kernel::Config','Kernel::System::DB','Kernel::System::JSON');
sub Configure { my ($Self)=@_; $Self->Description('Validate D724 API authorization storage and invariants.'); $Self->AddOption(Name=>'json',Description=>'Print JSON.',Required=>0,HasValue=>0); return }
sub StatusData {
    my ($Self)=@_; my $DB=$Kernel::OM->Get('Kernel::System::DB'); my %Table=map { $_=>1 } $DB->ListTables();
    my @Needed=qw(d724_api_client d724_api_token d724_api_rate); my @Missing=grep { !$Table{$_} } @Needed;
    my %Count=(Clients=>0,ActiveClients=>0,Tokens=>0,ActiveTokens=>0,InvalidTenantClients=>0,InvalidSecretHashes=>0,InvalidTokenHashes=>0,DuplicateRateWindows=>0,RateWindowUnique=>0,QueryErrors=>0);
    if(!@Missing){
        $DB->Prepare(SQL=>"SELECT COUNT(*), SUM(status = 'active') FROM d724_api_client"); @Count{qw(Clients ActiveClients)}=$DB->FetchrowArray();
        $DB->Prepare(SQL=>"SELECT COUNT(*), SUM(status = 'active' AND expires_at > current_timestamp) FROM d724_api_token"); @Count{qw(Tokens ActiveTokens)}=$DB->FetchrowArray();
        $DB->Prepare(SQL=>"SELECT COUNT(*) FROM d724_api_client c LEFT JOIN d724_tenant t ON t.key_name=c.tenant_id AND t.status='active' WHERE t.key_name IS NULL"); ($Count{InvalidTenantClients})=$DB->FetchrowArray();
        $DB->Prepare(SQL=>"SELECT COUNT(*) FROM d724_api_client WHERE secret_hash NOT LIKE 'BCRYPT:%'"); ($Count{InvalidSecretHashes})=$DB->FetchrowArray();
        if($DB->Prepare(SQL=>q{SELECT COUNT(*) FROM d724_api_token WHERE token_hash NOT REGEXP '^[0-9a-f]{64}$'})){($Count{InvalidTokenHashes})=$DB->FetchrowArray()}else{$Count{QueryErrors}++}
        $DB->Prepare(SQL=>'SELECT COUNT(*) FROM (SELECT client_id, window_start, COUNT(*) n FROM d724_api_rate GROUP BY client_id, window_start HAVING n > 1) d'); ($Count{DuplicateRateWindows})=$DB->FetchrowArray();
        $DB->Prepare(SQL=>"SELECT COUNT(*) FROM information_schema.statistics WHERE table_schema=DATABASE() AND table_name='d724_api_rate' AND index_name='d724_api_rate_window'"); my ($IndexColumns)=$DB->FetchrowArray(); $Count{RateWindowUnique}=($IndexColumns//0)==2?1:0;
    }
    $_//=0 for values %Count;
    my $Success=!@Missing && $Count{RateWindowUnique} && !$Count{QueryErrors} && !$Count{InvalidTenantClients} && !$Count{InvalidSecretHashes} && !$Count{InvalidTokenHashes} && !$Count{DuplicateRateWindows};
    return {Success=>$Success?1:0,Package=>'D724API',Version=>'0.1.2',Enabled=>$Kernel::OM->Get('Kernel::Config')->Get('D724::API::Enabled')?1:0,MissingTables=>\@Missing,Counts=>\%Count};
}
sub Run { my ($Self)=@_; my $S=$Self->StatusData(); if($Self->GetOption('json')){$Self->Print($Kernel::OM->Get('Kernel::System::JSON')->Encode(Data=>$S,SortKeys=>1,Pretty=>1)."\n")}else{$Self->Print('D724API 0.1.2: '.($S->{Success}?'OK':'FAILED')."\n")} return $S->{Success}?$Self->ExitCodeOk():$Self->ExitCodeError() }
1;
