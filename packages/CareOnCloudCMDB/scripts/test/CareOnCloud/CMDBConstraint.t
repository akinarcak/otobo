# --
# SPDX-License-Identifier: GPL-3.0-only
# --
use v5.24;use strict;use warnings;use Test2::V0;use Kernel::System::UnitTest::RegisterOM;
$Kernel::OM->ObjectParamAdd('Kernel::System::UnitTest::Helper'=>{RestoreDatabase=>1});
my$H=$Kernel::OM->Get('Kernel::System::UnitTest::Helper');my$DB=$Kernel::OM->Get('Kernel::System::DB');my$S=$Kernel::OM->Get('Kernel::System::CareOnCloud::CMDBConstraint')->Ensure();
ok($S->{Success},'all CMDB parent relations have tenant-paired constraints');my$ConstraintCount=grep{$S->{Constraints}->{$_}}keys%{$S->{Constraints}};is($ConstraintCount,8,'eight composite constraints are structurally exact');
my$X=lc$H->GetRandomID();my($A,$B)=("cmdb-a-$X","cmdb-b-$X");for my$T($A,$B){my@V=($T,"CMDB $T",1,1);my@Q=map{\$_}@V;ok($DB->Do(SQL=>q{INSERT INTO careoncloud_tenant (key_name,name,status,version,create_time,create_by,change_time,change_by) VALUES (?,?,'active',1,current_timestamp,?,current_timestamp,?)},Bind=>\@Q),'fixture tenant created')}
my@TV=($A,"type-$X",1,1);my@TB=map{\$_}@TV;ok($DB->Do(SQL=>q{INSERT INTO careoncloud_ci_type (tenant_id,key_name,name,description,status,attribute_schema_json,version,create_time,create_by,change_time,change_by) VALUES (?,?,'Server','fixture','active','{"version":1,"fields":[]}',1,current_timestamp,?,current_timestamp,?)},Bind=>\@TB),'tenant A CI type created');$DB->Prepare(SQL=>'SELECT id FROM careoncloud_ci_type WHERE tenant_id=? AND key_name=?',Bind=>[\$A,\$TV[1]],Limit=>1);my($TypeID)=$DB->FetchrowArray();my@CV=($B,$TypeID,"ci-$X",1,1);my@CB=map{\$_}@CV;ok(!$DB->Do(SQL=>q{INSERT INTO careoncloud_ci (tenant_id,type_id,key_name,name,description,status,criticality,attributes_json,version,create_time,create_by,change_time,change_by) VALUES (?,?,?,'Cross tenant','must fail','active','medium','{}',1,current_timestamp,?,current_timestamp,?)},Bind=>\@CB),'database rejects cross-tenant CI-to-type relation');
done_testing;
