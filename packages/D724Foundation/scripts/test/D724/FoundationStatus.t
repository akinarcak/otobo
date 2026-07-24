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

my $CommandObject = $Kernel::OM->Get(
    'Kernel::System::Console::Command::Admin::D724::FoundationStatus'
);

my ( $JSONString, undef, $ExitCode ) = capture {
    return $CommandObject->Execute('--json');
};

is( $ExitCode, 0, 'status command succeeds' );
my $Status = $Kernel::OM->Get('Kernel::System::JSON')->Decode( Data => $JSONString );
is( ref $Status, 'HASH', 'status command emits a JSON object' );
ok( $Status->{Success}, 'JSON status is successful' );
is( $Status->{Manifest}->{Package}, 'D724Foundation', 'JSON manifest identifies the package' );
is( $Status->{Manifest}->{License}, 'GPL-3.0-only', 'JSON manifest identifies the license' );

done_testing;
