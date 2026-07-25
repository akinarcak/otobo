# --
# SPDX-License-Identifier: GPL-3.0-only
# --
package Kernel::System::D724::ChangeConstraint;
use v5.24;use strict;use warnings;
our $VERSION='0.1.1';our @ObjectDependencies=('Kernel::System::DB');
my $Name='d724_fk_change_instance_tenant';
my @Wrong=qw(FK_d724_change_tenant_id_tenant_id FK_d724_change_service_instance_id_id);
sub new{return bless{},$_[0]}
sub Ensure{my($S)=@_;my$DB=$Kernel::OM->Get('Kernel::System::DB');for my$N(@Wrong){$DB->Prepare(SQL=>'SELECT COUNT(*) FROM information_schema.table_constraints WHERE constraint_schema=DATABASE() AND table_name=? AND constraint_name=?',Bind=>[\'d724_change',\$N]);my@R=$DB->FetchrowArray();return{Success=>0,Error=>'CONSTRAINT_DROP_FAILED',Constraint=>$N}if$R[0]&&!$DB->Do(SQL=>"ALTER TABLE d724_change DROP FOREIGN KEY $N")}my$St=$S->StatusGet();return$St if$St->{Success};return{Success=>0,Error=>'CONSTRAINT_CREATE_FAILED',Constraint=>$Name}if!$DB->Do(SQL=>"ALTER TABLE d724_change ADD CONSTRAINT $Name FOREIGN KEY (tenant_id, service_instance_id) REFERENCES d724_service_instance (tenant_id, id)");return$S->StatusGet()}
sub StatusGet{my($S)=@_;my$DB=$Kernel::OM->Get('Kernel::System::DB');$DB->Prepare(SQL=>q{SELECT column_name,referenced_table_name,referenced_column_name FROM information_schema.key_column_usage WHERE table_schema=DATABASE() AND table_name='d724_change' AND constraint_name=? ORDER BY ordinal_position},Bind=>[\$Name]);my@F;while(my@R=$DB->FetchrowArray()){push@F,join'>',$R[0],$R[1].'.'.$R[2]}my$Good=join('|',@F)eq'service_instance_id>d724_service_instance.id|tenant_id>d724_service_instance.tenant_id'||join('|',@F)eq'tenant_id>d724_service_instance.tenant_id|service_instance_id>d724_service_instance.id';return{Success=>$Good?1:0,Constraint=>$Name,Columns=>\@F}}
1;
