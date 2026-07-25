# --
# SPDX-License-Identifier: GPL-3.0-only
# --
use v5.24;use strict;use warnings;use Test2::V0;use Kernel::System::UnitTest::RegisterOM;
my$L=$Kernel::OM->Get('Kernel::Output::HTML::Layout');
$L->Block(Name=>'TenantOption',Data=>{TenantID=>'showcase-bank',Selected=>'selected'});
my$R={TenantID=>'showcase-bank',ChangeID=>42,ChangeNumber=>'CHG-0000000042',Title=>'<script>alert(1)</script>',ChangeType=>'normal',CreateTime=>'2026-07-25 17:00:00',RiskLevel=>'high',RiskScore=>12,Impact=>'critical',Likelihood=>'high',Status=>'awaiting_approval',Version=>2,ImplementationPlan=>'Deploy signed image',TestPlan=>'Validate traffic',BackoutPlan=>'Restore image'};
$L->Block(Name=>'ChangeRow',Data=>$R);$L->Block(Name=>'CABAction',Data=>$R);
my$H=$L->Output(TemplateFile=>'AgentD724Change',Data=>{TenantID=>'showcase-bank',Total=>1,Awaiting=>1,Scheduled=>0,Implementing=>0,CanManage=>1});
like($H,qr{CareOnCloud Change Enablement},'workbench title');like($H,qr{CHG-0000000042},'change number');like($H,qr{&lt;script&gt;alert\(1\)&lt;/script&gt;},'change title escaped');unlike($H,qr{<script>alert},'untrusted markup not rendered');like($H,qr{value="approved"},'CAB approval action');like($H,qr{name="ChallengeToken"},'CSRF token included');done_testing;
