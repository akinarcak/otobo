# --
# SPDX-License-Identifier: GPL-3.0-only
# --
use v5.24;use strict;use warnings;use utf8;use Test2::V0;use Kernel::System::UnitTest::RegisterOM;
my$L=$Kernel::OM->Get('Kernel::Output::HTML::Layout');
$L->Block(Name=>'TenantOption',Data=>{TenantID=>'demo-bank',Name=>'[DEMO] Bank <A>',Selected=>'selected'});
$L->Block(Name=>'RequestStatusRow',Data=>{Status=>'in_progress <x>',Count=>7});
$L->Block(Name=>'CatalogItemRow',Data=>{Name=>'Cloud <script>x</script>',Count=>4});
$L->Block(Name=>'CommitmentRow',Data=>{ObjectiveType=>'resolution',Status=>'warning',Count=>2});
my$H=$L->Output(TemplateFile=>'AgentD724Operations',Data=>{TenantID=>'demo-bank',From=>'2026-07-01',To=>'2026-07-31',Requests=>7,Commitments=>10,BreachedCommitments=>1,Compliance=>90});
like($H,qr{CareOnCloud Operations Center},'operations title rendered');like($H,qr{\[DEMO\]\s*Bank\s*&lt;A&gt;},'tenant label escaped');like($H,qr{Cloud\s*&lt;script&gt;x&lt;/script&gt;},'catalog label escaped');unlike($H,qr{<script>x</script>},'untrusted markup never rendered');like($H,qr{90%},'SLA compliance KPI rendered');like($H,qr{name="TenantID"},'tenant scope is submitted explicitly');done_testing;
