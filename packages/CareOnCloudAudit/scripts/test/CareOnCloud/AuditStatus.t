# --
# Copyright (C) 2026 Data Market Bilgi Hizmetleri A.S.
# SPDX-License-Identifier: GPL-3.0-only
# --
use v5.24; use strict; use warnings; use Test2::V0; use Kernel::System::UnitTest::RegisterOM;
my $Command=$Kernel::OM->Get('Kernel::System::Console::Command::Admin::CareOnCloud::AuditStatus');
my $Status; { no warnings 'redefine'; local *Kernel::System::Console::Command::Admin::CareOnCloud::AuditStatus::Print=sub{my($Self,$Text)=@_;$Status=$Kernel::OM->Get('Kernel::System::JSON')->Decode(Data=>$Text)}; is($Command->Execute('--json'),0,'audit status succeeds') }
ok($Status->{Success},'audit schema is healthy'); is($Status->{Package},'CareOnCloudAudit','status identifies package'); is($Status->{Version},'0.2.1','status identifies version'); is([sort keys %{$Status->{Tables}}],[qw(careoncloud_audit_event careoncloud_audit_head)],'both audit tables reported');
done_testing;
