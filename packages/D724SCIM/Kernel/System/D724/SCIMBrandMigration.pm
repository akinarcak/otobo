# --
# SPDX-License-Identifier: GPL-3.0-only
# --
package Kernel::System::D724::SCIMBrandMigration;
use v5.24;use strict;use warnings;
our$VERSION='0.2.0';our@ObjectDependencies=('Kernel::System::DB');
sub new{return bless{},$_[0]}
sub Ensure{my($S)=@_;my$DB=$Kernel::OM->Get('Kernel::System::DB');my$St=$S->StatusGet();if(!$St->{NativeColumn}){return{Success=>0,Error=>'NATIVE_COLUMN_CREATE_FAILED'}if!$DB->Do(SQL=>'ALTER TABLE d724_scim_user ADD COLUMN native_user_id INTEGER NULL AFTER active')}$St=$S->StatusGet();if($St->{LegacyColumn}){return{Success=>0,Error=>'NATIVE_VALUE_COPY_FAILED'}if!$DB->Do(SQL=>'UPDATE d724_scim_user SET native_user_id=careoncloud_user_id WHERE native_user_id IS NULL');return{Success=>0,Error=>'LEGACY_COLUMN_DROP_FAILED'}if!$DB->Do(SQL=>'ALTER TABLE d724_scim_user DROP COLUMN careoncloud_user_id')}return$S->StatusGet()}
sub StatusGet{my($S)=@_;my$DB=$Kernel::OM->Get('Kernel::System::DB');$DB->Prepare(SQL=>q{SELECT column_name FROM information_schema.columns WHERE table_schema=DATABASE() AND table_name='d724_scim_user' AND column_name IN ('native_user_id','careoncloud_user_id')});my%H;while(my($N)=$DB->FetchrowArray()){$H{$N}=1}return{Success=>$H{native_user_id}&&!$H{careoncloud_user_id}?1:0,NativeColumn=>$H{native_user_id}?1:0,LegacyColumn=>$H{careoncloud_user_id}?1:0}}
1;
