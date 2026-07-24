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
    'Kernel::System::Console::Command::Admin::D724::CatalogStatus'
);
my ( $JSONString, undef, $ExitCode ) = capture {
    return $CommandObject->Execute('--json');
};

is( $ExitCode, 0, 'catalog status command succeeds' );
my $Status = $Kernel::OM->Get('Kernel::System::JSON')->Decode( Data => $JSONString );
ok( $Status->{Success}, 'catalog repository is healthy' );
is( $Status->{Package}, 'D724Catalog', 'status identifies package' );
is( $Status->{Version}, '0.2.1', 'status identifies version' );
is(
    [ sort keys %{ $Status->{Tables} } ],
    [qw(d724_catalog_item d724_catalog_item_schema d724_service d724_service_offering)],
    'all catalog tables are reported',
);
ok( !( grep { !$_ } values %{ $Status->{Tables} } ), 'all catalog tables exist' );

done_testing;
