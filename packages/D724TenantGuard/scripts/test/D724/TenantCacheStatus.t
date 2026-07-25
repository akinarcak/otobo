# --
# Copyright (C) 2026 Data Market Bilgi Hizmetleri A.S.
# SPDX-License-Identifier: GPL-3.0-only
# --
use v5.24;
use strict;
use warnings;
use Capture::Tiny qw(capture);
use Test2::V0;
use Kernel::System::UnitTest::RegisterOM;

$Kernel::OM->ObjectParamAdd( 'Kernel::System::UnitTest::Helper' => { RestoreDatabase => 1 } );
my $Helper = $Kernel::OM->Get('Kernel::System::UnitTest::Helper');
$Helper->ConfigSettingChange( Key => 'D724::TenantCache::Enabled', Value => 1 );
$Helper->ConfigSettingChange( Key => 'D724::TenantCache::MaximumTTLSeconds', Value => 600 );
my $Command = $Kernel::OM->Get('Kernel::System::Console::Command::Admin::D724::TenantCacheStatus');
my ( $Output, undef, $Exit ) = capture { return $Command->Execute('--json') };
is( $Exit, 0, 'healthy cache configuration exits successfully' );
my $Status = $Kernel::OM->Get('Kernel::System::JSON')->Decode( Data => $Output );
ok( $Status->{Success}, 'status is healthy' );
is( $Status->{MaximumTTLSeconds}, 600, 'configured maximum TTL is reported' );
ok( $Status->{BackendAvailable}, 'OTOBO persistent cache backend is available' );
ok( $Status->{BackendModule}, 'configured backend module is reported' );
is( $Status->{NamespaceVersion}, 1, 'namespace contract version is reported' );
ok( $Status->{PersistentOnly}, 'adapter persistent-only behavior is reported' );

$Helper->ConfigSettingChange( Key => 'D724::TenantCache::MaximumTTLSeconds', Value => 0 );
my ( undef, undef, $InvalidExit ) = capture { return $Command->Execute('--json') };
is( $InvalidExit, 1, 'invalid TTL configuration fails status command' );

done_testing;
