# --
# Copyright (C) 2026 Data Market Bilgi Hizmetleri A.S.
# SPDX-License-Identifier: GPL-3.0-only
# --
use v5.24; use strict; use warnings; use Test2::V0; use Kernel::System::UnitTest::RegisterOM;
$Kernel::OM->ObjectParamAdd('Kernel::System::UnitTest::Helper'=>{RestoreDatabase=>1});
my $Helper=$Kernel::OM->Get('Kernel::System::UnitTest::Helper');
$Helper->ConfigSettingChange(Key=>'D724::Audit::Enabled',Value=>1);
$Helper->ConfigSettingChange(Key=>'D724::Audit::IPHashSalt',Value=>'unit-test-secret-salt');
$Helper->ConfigSettingChange(Key=>'CheckEmailAddresses',Value=>0);
my $Suffix=lc $Helper->GetRandomID(); my $A="audit-a-$Suffix"; my $B="audit-b-$Suffix";
my $User=$Kernel::OM->Get('Kernel::System::User');
my $AuditorID=$User->UserAdd(UserFirstname=>'Audit',UserLastname=>'Reader',UserLogin=>"audit-reader-$Suffix",UserEmail=>"audit-reader-$Suffix\@example.test",ValidID=>1,ChangeUserID=>1) || die;
my $DB=$Kernel::OM->Get('Kernel::System::DB');
for my $Tenant($A,$B){my @V=($Tenant,"Tenant $Tenant",'active',1,$AuditorID,$AuditorID);my @B=map{\$_}@V;$DB->Do(SQL=>'INSERT INTO d724_tenant (key_name,name,status,version,create_time,create_by,change_time,change_by) VALUES (?,?,?, ?,current_timestamp,?,current_timestamp,?)',Bind=>\@B)||die}
for my $Role([$A,$AuditorID,'auditor'],[$B,$AuditorID,'agent']){my($T,$U,$R)=@{$Role};my @V=($T,$U,$R,'active',$AuditorID,$AuditorID);my @B=map{\$_}@V;$DB->Do(SQL=>'INSERT INTO d724_tenant_agent_role (tenant_id,user_id,role_name,status,create_time,create_by,change_time,change_by) VALUES (?,?,?,?,current_timestamp,?,current_timestamp,?)',Bind=>\@B)||die}
my $Audit=$Kernel::OM->Get('Kernel::System::D724::Audit');
my $One=$Audit->Record(TenantID=>$A,ActorType=>'customer',ActorID=>'customer:test',Action=>'request.created',ObjectType=>'request',ObjectID=>'101',CorrelationID=>'REQ-101',FromState=>'',ToState=>'awaiting_approval',Outcome=>'success',SourceIP=>'10.1.2.3',Details=>{catalog_item_id=>7});
ok($One->{Success},'first normalized audit event is recorded'); is($One->{Data}->{Sequence},1,'tenant chain begins at sequence one'); is($One->{Data}->{PreviousHash},'0'x64,'tenant chain begins with zero hash');
my $Two=$Audit->Record(TenantID=>$A,ActorType=>'agent',ActorID=>"agent:$AuditorID",Action=>'request.approved',ObjectType=>'request',ObjectID=>'101',CorrelationID=>'REQ-101',FromState=>'awaiting_approval',ToState=>'in_fulfillment',Details=>{decision=>'approved'},EventTime=>'2026-07-24 12:00:00');
ok($Two->{Success},'second audit event is recorded'); is($Two->{Data}->{Sequence},2,'sequence advances monotonically'); is($Two->{Data}->{PreviousHash},$One->{Data}->{EventHash},'event links to previous hash');
ok($Audit->Record(TenantID=>$B,ActorType=>'system',ActorID=>'system:test',Action=>'request.created',ObjectType=>'request',ObjectID=>'201',Details=>{})->{Success},'another tenant has independent chain');
my $Page=$Audit->List(UserID=>$AuditorID,TenantID=>$A,Limit=>1); ok($Page->{Success},'auditor reads own tenant audit'); is(scalar @{$Page->{Data}},1,'pagination limit is honored'); is($Page->{NextSequence},1,'stable sequence cursor is returned');
my $Next=$Audit->List(UserID=>$AuditorID,TenantID=>$A,AfterSequence=>$Page->{NextSequence},Limit=>10); is([map{$_->{Action}}@{$Next->{Data}}],['request.approved'],'cursor returns only later events');
is($Audit->List(UserID=>$AuditorID,TenantID=>$B)->{Error},'FORBIDDEN','agent role cannot read foreign tenant audit');
my $Object=$Audit->List(UserID=>$AuditorID,TenantID=>$A,ObjectType=>'request',ObjectID=>'101'); is(scalar @{$Object->{Data}},2,'object filter remains tenant scoped');
my $Export=$Audit->ExportNDJSON(UserID=>$AuditorID,TenantID=>$A); is($Export->{ContentType},'application/x-ndjson','export declares NDJSON'); is(scalar(grep{length}split /\n/,$Export->{Content}),2,'export emits one JSON object per line'); unlike($Export->{Content},qr{10\.1\.2\.3},'source IP is never exported in clear text');
my $Verify=$Audit->Verify(UserID=>$AuditorID,TenantID=>$A); ok($Verify->{Valid},'hash chain and head verify'); is($Verify->{Count},2,'verification reports chain length');
my($EventID);$DB->Prepare(SQL=>'SELECT id FROM d724_audit_event WHERE tenant_id = ? AND sequence_no = 1',Bind=>[\$A]);($EventID)=$DB->FetchrowArray();my($Changed,$ID)=('tampered',$EventID);$DB->Do(SQL=>'UPDATE d724_audit_event SET to_state = ? WHERE id = ?',Bind=>[\$Changed,\$ID]);
my $Tampered=$Audit->Verify(UserID=>$AuditorID,TenantID=>$A); ok(!$Tampered->{Valid},'tampering is detected'); is($Tampered->{Error},'EVENT_HASH_MISMATCH','tampering failure is explicit');
is($Audit->Record(TenantID=>$A,ActorType=>'agent',ActorID=>'a',Action=>'Bad Action',ObjectType=>'request',ObjectID=>'1',Details=>{})->{Error},'ACTION_INVALID','invalid event vocabulary fails closed');
$Helper->ConfigSettingChange(Key=>'D724::Audit::Enabled',Value=>0); is($Audit->List(UserID=>$AuditorID,TenantID=>$A)->{Error},'AUDIT_DISABLED','disabled audit fails closed');
done_testing;
