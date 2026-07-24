# --
# Copyright (C) 2026 Data Market Bilgi Hizmetleri A.S.
# SPDX-License-Identifier: GPL-3.0-only
# --
use v5.24; use strict; use warnings; use Test2::V0; use Kernel::System::UnitTest::RegisterOM;
my $Command=$Kernel::OM->Get('Kernel::System::Console::Command::Admin::D724::APIStatus');
my $Status=$Command->StatusData();
ok($Status->{Success},'API storage status succeeds');
is($Status->{Version},'0.3.0','status reports package version');
ok($Status->{Transport}->{CanonicalMount},'canonical /api/v1 PSGI mount is installed');
ok($Status->{Transport}->{OpenAPI31},'OpenAPI 3.1 contract is installed and parseable');
is($Status->{MissingTables},[],'all API tables exist');
ok($Status->{Counts}->{RateWindowUnique},'client and minute rate window has composite unique index');
is($Status->{Counts}->{InvalidTenantClients},0,'all clients reference active tenants');
is($Status->{Counts}->{InvalidSecretHashes},0,'all stored client secrets use bcrypt');
is($Status->{Counts}->{InvalidTokenHashes},0,'all stored tokens are SHA-256 digests');
is($Status->{Counts}->{DuplicateRateWindows},0,'rate windows are unique');
is($Status->{Counts}->{QueryErrors},0,'health queries complete without database errors');
done_testing;
