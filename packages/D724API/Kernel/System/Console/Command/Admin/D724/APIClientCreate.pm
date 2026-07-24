# --
# Copyright (C) 2026 Data Market Bilgi Hizmetleri A.S.
# SPDX-License-Identifier: GPL-3.0-only
# --
package Kernel::System::Console::Command::Admin::D724::APIClientCreate;
use v5.24; use strict; use warnings; use parent qw(Kernel::System::Console::BaseCommand);
our $VERSION = '0.1.0'; our @ObjectDependencies = ('Kernel::System::D724::APIAuth','Kernel::System::D724::TenantDirectory');
sub Configure { my ($Self)=@_; $Self->Description('Create a tenant-bound API client and print its secret exactly once.'); for my $Spec ([tenant_id=>'tenant-id'],[name=>'name'],[role=>'role'],[actor_user_id=>'actor-user-id']) { $Self->AddOption(Name=>$Spec->[1],Description=>$Spec->[1],Required=>1,HasValue=>1) } $Self->AddOption(Name=>'token-ttl',Description=>'Token TTL seconds.',Required=>0,HasValue=>1); $Self->AddOption(Name=>'rate-limit',Description=>'Requests per minute.',Required=>0,HasValue=>1); $Self->AddOption(Name=>'confirm',Description=>'Confirm secret creation.',Required=>1,HasValue=>0); return }
sub Run { my ($Self)=@_; return $Self->ExitCodeError() if !$Self->GetOption('confirm'); my $UserID=$Self->GetOption('actor-user-id'); my $Context=$Kernel::OM->Get('Kernel::System::D724::TenantDirectory')->ContextGet(UserID=>$UserID); if(!$Context->{Success}){$Self->PrintError("Actor context failed: $Context->{Error}");return $Self->ExitCodeError()} my $Result=$Kernel::OM->Get('Kernel::System::D724::APIAuth')->ClientCreate(Subject=>$Context->{Subject},TenantID=>$Self->GetOption('tenant-id'),Name=>$Self->GetOption('name'),Role=>$Self->GetOption('role'),UserID=>$UserID,TokenTTL=>$Self->GetOption('token-ttl')//900,RateLimit=>$Self->GetOption('rate-limit')//60); if(!$Result->{Success}){$Self->PrintError("API client create failed: $Result->{Error}");return $Self->ExitCodeError()} $Self->Print("ClientID=$Result->{Data}->{ClientID}\nClientSecret=$Result->{Data}->{ClientSecret}\nStore this secret now; it cannot be retrieved again.\n"); return $Self->ExitCodeOk() }
1;
