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

my $Command = $Kernel::OM->Get('Kernel::System::Console::Command::Admin::CareOnCloud::ReportExport');
my ( undef, $Error, $Exit ) = capture {
    return $Command->Execute(
        '--tenant-id', 'careoncloud-demo', '--from', '2026-01-01', '--to', '2026-12-31',
        '--actor-user-id', '999999999', '--format', 'csv',
    );
};
is( $Exit, 1, 'configured report command returns domain failure as error exit' );
like( $Error, qr{Report export failed}, 'command reaches reporting service after option validation' );

done_testing;
