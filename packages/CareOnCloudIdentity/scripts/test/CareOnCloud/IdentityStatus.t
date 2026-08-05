# --
# Copyright (C) 2026 Data Market Bilgi Hizmetleri A.S.
# SPDX-License-Identifier: GPL-3.0-only
# --
use v5.24; use strict; use warnings;
use Capture::Tiny qw(capture); use Test2::V0; use Kernel::System::UnitTest::RegisterOM;
my $Command=$Kernel::OM->Get('Kernel::System::Console::Command::Admin::CareOnCloud::IdentityStatus');
my($JSON,undef,$Exit)=capture{return $Command->Execute('--json')};
is($Exit,0,'identity status succeeds');
my $Data=$Kernel::OM->Get('Kernel::System::JSON')->Decode(Data=>$JSON);
ok($Data->{Success},'identity trust boundary is healthy');
is($Data->{Version},'0.3.0','identity package version is reported');
is([sort keys %{$Data->{Tables}}],[qw(careoncloud_federated_identity careoncloud_identity_provider careoncloud_oidc_flow)],'identity tables are reported');
done_testing;
