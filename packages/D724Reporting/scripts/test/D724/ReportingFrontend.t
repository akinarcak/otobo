# --
# SPDX-License-Identifier: GPL-3.0-only
# --
use v5.24;use strict;use warnings;use utf8;use Test2::V0;use Kernel::System::UnitTest::RegisterOM;
my$L=$Kernel::OM->Get('Kernel::Output::HTML::Layout');
$L->Block(Name=>'TenantOption',Data=>{TenantID=>'demo-bank',Name=>'[DEMO] Bank <A>',Selected=>'selected'});
$L->Block(Name=>'RequestStatusRow',Data=>{Status=>'in_progress <x>',Count=>7});
$L->Block(Name=>'CatalogItemRow',Data=>{Name=>'Cloud <script>x</script>',Count=>4});
$L->Block(Name=>'CommitmentRow',Data=>{ObjectiveType=>'resolution',Status=>'warning',Count=>2});
for my $Option ( [ status => 'Status' ], [ service => 'Service category' ] ) { $L->Block(Name=>'DimensionOption',Data=>{Key=>$Option->[0],Label=>$Option->[1],Selected=>$Option->[0] eq 'status'?'selected':q{}}); }
for my $Option ( [ requests => 'Requests' ], [ breaches => 'Breaches' ] ) { $L->Block(Name=>'MetricOption',Data=>{Key=>$Option->[0],Label=>$Option->[1],Selected=>'selected'}); }
$L->Block(Name=>'SavedReportOption',Data=>{ReportID=>12,Name=>'Executive <unsafe>',Visibility=>'shared',Selected=>'selected'});
my$H=$L->Output(TemplateFile=>'AgentD724Operations',Data=>{TenantID=>'demo-bank',From=>'2026-07-01',To=>'2026-07-31',Status=>q{},Requests=>7,Commitments=>10,BreachedCommitments=>1,Compliance=>90,SavedNotice=>1,CustomColumns=>['Status','Requests'],CustomRows=>[{Values=>['fulfilled <x>',7]}]});
like($H,qr{CareOnCloud Operations Center},'operations title rendered');like($H,qr{\[DEMO\]\s*Bank\s*&lt;A&gt;},'tenant label escaped');like($H,qr{Cloud\s*&lt;script&gt;x&lt;/script&gt;},'catalog label escaped');unlike($H,qr{<script>x</script>},'untrusted markup never rendered');like($H,qr{90%},'SLA compliance KPI rendered');like($H,qr{name="TenantID"},'tenant scope is submitted explicitly');like($H,qr{id="D724ReportDimensions"},'custom dimensions selector rendered');like($H,qr{id="D724ReportMetrics"},'custom metrics selector rendered');like($H,qr{fulfilled\s*&lt;x&gt;},'custom report values escaped');like($H,qr{id="D724SavedReport"},'saved report selector rendered');like($H,qr{Executive\s*&lt;unsafe&gt;},'saved report name escaped');like($H,qr{name="ChallengeToken"},'saved report mutation carries CSRF token');done_testing;
