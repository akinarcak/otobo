# --
# CareOnCloud ESM enterprise service management platform.
# Copyright (C) 2026 Data Market Bilgi Hizmetleri A.S.
# SPDX-License-Identifier: GPL-3.0-only
# --

use v5.24;
use strict;
use warnings;
use Test2::V0;
use Kernel::System::UnitTest::RegisterOM;

my $Layout = $Kernel::OM->Get('Kernel::Output::HTML::Layout');
$Layout->Block( Name => 'TenantOption', Data => { TenantID => 'tenant-<script>', Selected => q{} } );
$Layout->Block(
    Name => 'PolicyRow',
    Data => {
        TenantID => 'tenant-a', PolicyID => 1, Version => 2, Key => 'standard-resolution',
        Name => 'Standard <img src=x>', CalendarID => 0, TargetSeconds => 14_400,
        WarningPercent => 80, PauseStatusesText => 'waiting_customer', Status => 'active',
    },
);
my $HTML = $Layout->Output( TemplateFile => 'AdminCareOnCloudCommitment', Data => { TenantID => 'tenant-a' } );
like( $HTML, qr{tenant-&lt;script&gt;}, 'tenant option is escaped' );
like( $HTML, qr{Standard &lt;img src=x&gt;}, 'policy name is escaped' );
unlike( $HTML, qr{<img src=x>}, 'policy markup is never rendered' );
is( scalar( () = $HTML =~ m{method="post"}g ), 2, 'create and update use POST forms' );
like( $HTML, qr{name="ExpectedVersion" value="2"}, 'policy update carries optimistic version' );

done_testing;
