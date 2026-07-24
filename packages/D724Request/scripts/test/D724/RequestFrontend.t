# --
# D724 ESM is an enterprise service management platform based on OTOBO.
# Copyright (C) 2026 Data Market Bilgi Hizmetleri A.S.
# SPDX-License-Identifier: GPL-3.0-only
# --

use v5.24;
use strict;
use warnings;
use Test2::V0;
use Kernel::System::UnitTest::RegisterOM;

my $Layout = $Kernel::OM->Get('Kernel::Output::HTML::Layout');
my $CustomerHTML = $Layout->Output(
    TemplateFile => 'CustomerD724Request',
    Data => { Request => {
        RequestNumber => 'REQ-1<script>', Status => 'awaiting_approval',
        Commitments => [ { ObjectiveType => 'response', ObjectiveKey => 'first-response', Status => 'running', WarningTime => '2026-07-27 11:00:00', DueTime => '2026-07-27 13:00:00' } ],
    } },
);
like( $CustomerHTML, qr{REQ-1&lt;script&gt;}, 'customer receipt escapes request number' );
unlike( $CustomerHTML, qr{REQ-1<script>}, 'customer receipt never renders request markup' );
like( $CustomerHTML, qr{2026-07-27 13:00:00}, 'customer receipt shows commitment due time' );

$Layout->Block( Name => 'Request', Data => { RequestNumber => 'REQ-2<img>', Status => 'in_fulfillment', RequesterID => 'customer:test' } );
$Layout->Block( Name => 'Approval', Data => { TenantID => 'tenant-a', RequestID => 2, Version => 1 } );
$Layout->Block( Name => 'Task', Data => { TenantID => 'tenant-a', TaskID => 3, Version => 1, Name => 'Prepare <b>device</b>', Status => 'pending' } );
$Layout->Block( Name => 'Commitment', Data => { ObjectiveType => 'response', ObjectiveKey => 'first-response', Status => 'warning', WarningTime => '2026-07-27 11:00:00', DueTime => '2026-07-27 13:00:00' } );
$Layout->Block( Name => 'ResponseAction', Data => { TenantID => 'tenant-a', RequestID => 2 } );
my $AgentHTML = $Layout->Output( TemplateFile => 'AgentD724Request', Data => { TenantID => 'tenant-a' } );
like( $AgentHTML, qr{REQ-2&lt;img&gt;}, 'agent workbench escapes request data' );
unlike( $AgentHTML, qr{Prepare <b>device</b>}, 'agent workbench never renders task markup' );
is( scalar( () = $AgentHTML =~ m{method="post"}g ), 2, 'approval and task writes use POST forms' );
like( $AgentHTML, qr{value="ApprovalDecide"}, 'approval action is rendered' );
like( $AgentHTML, qr{value="TaskUpdate"}, 'task action is rendered' );
like( $AgentHTML, qr{<strong>response / first-response: warning</strong>}, 'agent workbench shows objective state' );
like( $AgentHTML, qr{value="ResponseRecord"}, 'agent workbench renders first-response signal action' );

done_testing;
