# --
# SPDX-License-Identifier: GPL-3.0-only
# --
use v5.24;use strict;use warnings;use utf8;use Test2::V0;use Kernel::System::UnitTest::RegisterOM;
my$L=$Kernel::OM->Get('Kernel::Output::HTML::Layout');
$L->Block(Name=>'TenantOption',Data=>{TenantID=>'demo-bank',Name=>'Demo <Bank>',Selected=>'selected'});
$L->Block(Name=>'ServiceRow',Data=>{TenantID=>'demo-bank',ServiceID=>17,CategoryName=>'Cloud & Hosting',ServiceName=>'Managed <Cloud>',ServiceDescription=>'Safe',ServiceStatus=>'active'});
$L->Block(Name=>'InstanceRow',Data=>{InstanceName=>'Production <script>x</script>',ServiceModel=>'fixed_scope',Criticality=>'critical',SupportGroupName=>'careon-demo-cloud',InstanceStatus=>'active'});
my$H=$L->Output(TemplateFile=>'AgentCareOnCloudServicePortfolio',Data=>{TenantID=>'demo-bank',ServiceID=>17,ServiceCount=>1,InstanceCount=>1});
like($H,qr{CareOnCloud Service Portfolio},'CareOnCloud portfolio title rendered');like($H,qr{Demo\s*&lt;Bank&gt;},'tenant name escaped');like($H,qr{Managed\s*&lt;Cloud&gt;},'service name escaped');like($H,qr{Production\s*&lt;script&gt;x&lt;/script&gt;},'instance name escaped');unlike($H,qr{<script>x</script>},'untrusted markup not rendered');like($H,qr{TenantID=demo-bank;ServiceID=17},'tenant-bound detail link rendered');done_testing;
