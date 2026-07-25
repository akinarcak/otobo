# --
# SPDX-License-Identifier: GPL-3.0-only
# --
package Kernel::System::D724::CMDBConstraint;
use v5.24;use strict;use warnings;
our $VERSION='0.1.2';our @ObjectDependencies=('Kernel::System::DB');
my@C=(
 {Name=>'d724_fk_category_service_category',Table=>'d724_service_category_service',Columns=>[qw(tenant_id category_id)],ForeignTable=>'d724_service_category',ForeignColumns=>[qw(tenant_id id)]},
 {Name=>'d724_fk_category_service_service',Table=>'d724_service_category_service',Columns=>[qw(tenant_id service_id)],ForeignTable=>'d724_service',ForeignColumns=>[qw(tenant_id id)]},
 {Name=>'d724_fk_instance_service_tenant',Table=>'d724_service_instance',Columns=>[qw(tenant_id service_id)],ForeignTable=>'d724_service',ForeignColumns=>[qw(tenant_id id)]},
 {Name=>'d724_fk_ci_type_tenant',Table=>'d724_ci',Columns=>[qw(tenant_id type_id)],ForeignTable=>'d724_ci_type',ForeignColumns=>[qw(tenant_id id)]},
 {Name=>'d724_fk_relation_source_tenant',Table=>'d724_ci_relation',Columns=>[qw(tenant_id source_ci_id)],ForeignTable=>'d724_ci',ForeignColumns=>[qw(tenant_id id)]},
 {Name=>'d724_fk_relation_target_tenant',Table=>'d724_ci_relation',Columns=>[qw(tenant_id target_ci_id)],ForeignTable=>'d724_ci',ForeignColumns=>[qw(tenant_id id)]},
 {Name=>'d724_fk_instance_ci_instance_tenant',Table=>'d724_service_instance_ci',Columns=>[qw(tenant_id service_instance_id)],ForeignTable=>'d724_service_instance',ForeignColumns=>[qw(tenant_id id)]},
 {Name=>'d724_fk_instance_ci_ci_tenant',Table=>'d724_service_instance_ci',Columns=>[qw(tenant_id ci_id)],ForeignTable=>'d724_ci',ForeignColumns=>[qw(tenant_id id)]},
);
sub new{return bless{},$_[0]}
sub Ensure{my($S)=@_;my$DB=$Kernel::OM->Get('Kernel::System::DB');my$St=$S->StatusGet();for my$C(@C){next if$St->{Constraints}->{$C->{Name}};my$SQL=sprintf'ALTER TABLE %s ADD CONSTRAINT %s FOREIGN KEY (%s) REFERENCES %s (%s)',$C->{Table},$C->{Name},join(', ',@{$C->{Columns}}),$C->{ForeignTable},join(', ',@{$C->{ForeignColumns}});return{Success=>0,Error=>'CONSTRAINT_CREATE_FAILED',Constraint=>$C->{Name}}if!$DB->Do(SQL=>$SQL)}return$S->StatusGet()}
sub StatusGet{my($S)=@_;my$DB=$Kernel::OM->Get('Kernel::System::DB');my%F;$DB->Prepare(SQL=>q{SELECT constraint_name,table_name,column_name,referenced_table_name,referenced_column_name,ordinal_position FROM information_schema.key_column_usage WHERE table_schema=DATABASE() AND table_name IN ('d724_service_category_service','d724_service_instance','d724_ci','d724_ci_relation','d724_service_instance_ci') AND referenced_table_name IS NOT NULL ORDER BY constraint_name,ordinal_position});while(my@R=$DB->FetchrowArray()){push@{$F{$R[0]}},{Table=>$R[1],Column=>$R[2],ForeignTable=>$R[3],ForeignColumn=>$R[4]}}my%V;for my$C(@C){my$Sig=join'|',map{"$_->{Table}.$_->{Column}>$_->{ForeignTable}.$_->{ForeignColumn}"}@{$F{$C->{Name}}//[]};my@E;for my$I(0..$#{$C->{Columns}}){push@E,$C->{Table}.'.'.$C->{Columns}->[$I].'>'.$C->{ForeignTable}.'.'.$C->{ForeignColumns}->[$I]}$V{$C->{Name}}=$Sig eq join('|',@E)?1:0}my$Success=(grep{!$V{$_}}keys%V)?0:1;return{Success=>$Success,Constraints=>\%V}}
1;
