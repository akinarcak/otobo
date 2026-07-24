# --
# D724 ESM is an enterprise service management platform based on OTOBO.
# Copyright (C) 2026 Data Market Bilgi Hizmetleri A.S.
# SPDX-License-Identifier: GPL-3.0-only
# --

use v5.24;
use strict;
use warnings;
use utf8;

use Capture::Tiny qw(capture);
use Test2::V0;
use Kernel::System::UnitTest::RegisterOM;

my $Command = $Kernel::OM->Get(
    'Kernel::System::Console::Command::Admin::D724::TenantGuardCheck'
);
my $JSON = $Kernel::OM->Get('Kernel::System::JSON');

my ( $AllowedJSON, undef, $AllowedExit ) = capture {
    return $Command->Execute(
        '--subject-id',      'agent-1',
        '--subject-tenant',  'tenant-a',
        '--role',            'agent',
        '--resource-tenant', 'tenant-a',
        '--action',          'case.update',
        '--json',
    );
};
is( $AllowedExit, 0, 'allowed decision exits successfully' );
my $Allowed = $JSON->Decode( Data => $AllowedJSON );
ok( $Allowed->{Allowed}, 'allowed JSON decision is true' );
is( $Allowed->{MatchedRole}, 'agent', 'allowed JSON exposes matched role for audit' );

my ( $DeniedJSON, undef, $DeniedExit ) = capture {
    return $Command->Execute(
        '--subject-id',      'agent-1',
        '--subject-tenant',  'tenant-a',
        '--role',            'agent',
        '--resource-tenant', 'tenant-b',
        '--action',          'case.read',
        '--json',
    );
};
is( $DeniedExit, 1, 'denied decision exits with error' );
my $Denied = $JSON->Decode( Data => $DeniedJSON );
ok( !$Denied->{Allowed}, 'denied JSON decision is false' );
is( $Denied->{Reason}, 'DENY_CROSS_TENANT', 'denied JSON exposes stable audit reason' );

done_testing;
