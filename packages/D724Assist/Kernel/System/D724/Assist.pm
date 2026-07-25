# --
# SPDX-License-Identifier: GPL-3.0-only
# --
package Kernel::System::D724::Assist;
use v5.24;use strict;use warnings;use utf8;
our $VERSION='0.1.1';
our @ObjectDependencies=('Kernel::Config','Kernel::System::D724::TenantDirectory','Kernel::System::D724::TenantGuard','Kernel::System::DB','Kernel::System::JSON');
sub new{return bless{},$_[0]}
sub Suggest{
 my($S,%P)=@_;return$S->_Error('ASSIST_DISABLED')if!$Kernel::OM->Get('Kernel::Config')->Get('D724::Assist::Enabled');
 return$S->_Error('TENANT_ID_INVALID')if($P{TenantID}//q{})!~m{\A[a-z0-9][a-z0-9._:-]{1,127}\z}smx;
 my$Q=$P{Query}//q{};$Q=~s{\A\s+|\s+\z}{}gsmx;return$S->_Error('QUERY_INVALID')if length($Q)<3||length($Q)>500||$Q=~m{[\x00-\x08\x0b\x0c\x0e-\x1f]}smx;
 my$Limit=$P{Limit}//5;return$S->_Error('LIMIT_INVALID')if$Limit!~m{\A[1-9]\z}smx||$Limit>10;
 my$Subject=$P{Subject};if(ref$Subject ne'HASH'&&$P{UserID}){my$C=$Kernel::OM->Get('Kernel::System::D724::TenantDirectory')->ContextGet(UserID=>$P{UserID});return$C if!$C->{Success};$Subject=$C->{Subject}}
 my$D=$Kernel::OM->Get('Kernel::System::D724::TenantGuard')->DecisionGet(Subject=>$Subject,Resource=>{TenantID=>$P{TenantID}},Action=>'case.read');return$S->_Error('FORBIDDEN',$D->{Reason})if!$D->{Allowed};
 my%QT=$S->_Tokens($Q);return$S->_Error('QUERY_TOO_GENERIC')if!keys%QT;
 my$T=$P{TenantID};my$Max=$Kernel::OM->Get('Kernel::Config')->Get('D724::Assist::CandidateLimit')//500;return$S->_Error('CANDIDATE_LIMIT_INVALID')if$Max!~m{\A[1-9][0-9]{1,3}\z}smx;
 my$DB=$Kernel::OM->Get('Kernel::System::DB');$DB->Prepare(SQL=>"SELECT r.id,r.request_number,r.catalog_item_id,c.name,r.status,r.answers_json,r.change_time FROM d724_request r INNER JOIN d724_catalog_item c ON c.tenant_id=r.tenant_id AND c.id=r.catalog_item_id WHERE r.tenant_id=? AND r.status='fulfilled' ORDER BY r.id DESC",Bind=>[\$T],Limit=>$Max);
 my@R;while(my($ID,$Number,$ItemID,$Item,$Status,$Answers,$Changed)=$DB->FetchrowArray()){
  my$Decoded=eval{$Kernel::OM->Get('Kernel::System::JSON')->Decode(Data=>$Answers)};my$Text=$Item.q{ }.$S->_Flatten($Decoded);my%CT=$S->_Tokens($Text);my$Overlap=grep{$CT{$_}}keys%QT;next if!$Overlap;my$Coverage=$Overlap/(keys%QT);my$Precision=$Overlap/(keys(%CT)||1);my$Score=int((0.8*$Coverage+0.2*$Precision)*100+0.5);next if$Score<10;
  my$RID=$ID;$DB->Prepare(SQL=>"SELECT result_comment FROM d724_request_task WHERE tenant_id=? AND request_id=? AND status='completed' AND result_comment<>'' ORDER BY id",Bind=>[\$T,\$RID],Limit=>3);my@Notes;while(my($N)=$DB->FetchrowArray()){$N=substr($N,0,500);push@Notes,$N}
  push@R,{RequestID=>0+$ID,RequestNumber=>$Number,CatalogItemID=>0+$ItemID,CatalogItem=>$Item,Status=>$Status,Changed=>$Changed,Confidence=>$Score,MatchedTerms=>$Overlap,QueryTerms=>0+keys(%QT),Evidence=>"$Overlap/".(keys%QT).' query terms matched',SolutionSummary=>@Notes?join(' · ',@Notes):'Completed request; no reusable resolution note recorded.'};
 }
 @R=sort{$b->{Confidence}<=>$a->{Confidence}||$b->{RequestID}<=>$a->{RequestID}}@R;splice(@R,$Limit)if@R>$Limit;return{Success=>1,Data=>\@R,Meta=>{TenantID=>$T,ExternalDataTransfer=>0,Algorithm=>'explainable-token-overlap-v1'}}
}
sub _Flatten{my($S,$X)=@_;return q{}if!defined$X;return join q{ },map{$S->_Flatten($_)}@$X if ref$X eq'ARRAY';return join q{ },map{$S->_Flatten($X->{$_})}sort keys%$X if ref$X eq'HASH';return ref$X?q{}:"$X"}
sub _Tokens{my($S,$X)=@_;$X=lc($X//q{});my%Stop=map{$_=>1}qw(ve ile için bir bu şu the and for from);my%T;for my$W($X=~m{([\p{L}\p{N}][\p{L}\p{N}._-]{2,})}gsmx){$T{$W}=1 if!$Stop{$W}}return%T}
sub _Error{my($S,$E,$R)=@_;return{Success=>0,Error=>$E,Reason=>$R//$E}}
1;
