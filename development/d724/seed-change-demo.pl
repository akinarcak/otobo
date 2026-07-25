#!/usr/bin/env perl
# --
# SPDX-License-Identifier: GPL-3.0-only
# --
use v5.24;use strict;use warnings;use FindBin qw($RealBin);use lib '/opt/otobo';use lib '/opt/otobo/Kernel/cpan-lib';use Kernel::System::ObjectManager;
local$Kernel::OM=Kernel::System::ObjectManager->new('Kernel::System::Log'=>{LogPrefix=>'CareOnCloud-change-demo'});
my$UserID=47;my$Directory=$Kernel::OM->Get('Kernel::System::D724::TenantDirectory');my$Change=$Kernel::OM->Get('Kernel::System::D724::Change');my$Ctx=$Directory->ContextGet(UserID=>$UserID);die"User context unavailable\n"if!$Ctx->{Success};my$Subject=$Ctx->{Subject};
my@Seed=(
 ['showcase-bank','Ana bankacilik veritabani felaket kurtarma gecisi','normal','critical','high','awaiting_approval','Aktif veritabanini ikincil veri merkezine kontrollu gecir.','Islem ve mutabakat kontrollerini calistir.','Birincil veri merkezine geri don.'],
 ['showcase-bank','SWIFT ag gecidi guvenlik yamasi','emergency','critical','critical','completed','Imzali guvenlik yamasini uygula.','Mesaj imza ve aktarim testlerini calistir.','Onceki sanal makine anlik goruntusune don.'],
 ['showcase-bank','Internet subesi TLS sertifika yenileme','standard','medium','low','scheduled','Yeni sertifikayi yuk dengeleyicilere dagit.','Sertifika zinciri ve mobil istemci testlerini yap.','Onceki sertifika paketini etkinlestir.'],
 ['showcase-retail','Magaza POS ag segmentasyonu','normal','high','medium','awaiting_approval','Pilot magazadan baslayarak POS VLAN ayirimini uygula.','Odeme, iade ve gun sonu akisini dogrula.','Eski VLAN ve guvenlik duvari kurallarini geri yukle.'],
 ['showcase-retail','Depo yonetim sistemi surum gecisi','normal','medium','medium','implementing','Uygulama servislerini sirali bicimde yeni surume al.','Stok, sevkiyat ve sayim senaryolarini calistir.','Veritabani yedegi ve onceki imaja geri don.'],
 ['showcase-retail','Magaza Wi-Fi denetleyici bakimi','standard','low','low','completed','Denetleyicileri ikili gruplar halinde guncelle.','Misafir ve kurumsal SSID baglantilarini dogrula.','Onceki firmware surumune geri don.'],
 ['showcase-fashion','E-ticaret kampanya kapasite artirimi','normal','high','high','awaiting_approval','Web ve siparis katmanini kampanya kapasitesine olcekle.','Yuk, sepet ve odeme testlerini calistir.','Ek kapasiteyi kaldir ve onceki ayarlara don.'],
 ['showcase-fashion','ERP koleksiyon kodlari aktarimi','standard','medium','low','scheduled','Yeni sezon urun kodlarini ERP sistemine aktar.','Urun, fiyat ve stok orneklemesini dogrula.','Aktarim paketini geri al.'],
 ['showcase-fashion','Magaza el terminali uygulama dagitimi','normal','medium','medium','cancelled','Yeni uygulamayi pilot cihaz grubuna dagit.','Barkod ve stok transfer testlerini calistir.','Onceki uygulama paketini geri yukle.'],
);
my%Allowed=map{$_=>1}@{$Subject->{TenantIDs}};my($Created,$Existing)=(0,0);
for my$S(@Seed){my($Tenant,$Title,$Type,$Impact,$Likelihood,$Target,$Impl,$Test,$Backout)=@$S;next if!$Allowed{$Tenant};my$List=$Change->List(Subject=>$Subject,TenantID=>$Tenant,UserID=>$UserID);die"List $Tenant failed: $List->{Error}\n"if!$List->{Success};if(grep{$_->{Title}eq$Title}@{$List->{Data}}){$Existing++;next}my$R=$Change->Create(Subject=>$Subject,TenantID=>$Tenant,UserID=>$UserID,Title=>$Title,Description=>"CareOnCloud ESM ticari demo degisiklik kaydi: $Title",ChangeType=>$Type,Impact=>$Impact,Likelihood=>$Likelihood,ImplementationPlan=>$Impl,TestPlan=>$Test,BackoutPlan=>$Backout);die"Create failed: $R->{Error}\n"if!$R->{Success};my$ID=$R->{Data}->{ChangeID};my$V=$R->{Data}->{Version};my$Q=$Change->Submit(Subject=>$Subject,TenantID=>$Tenant,UserID=>$UserID,ChangeID=>$ID,ExpectedVersion=>$V);die"Submit failed: $Q->{Error}\n"if!$Q->{Success};$V=$Q->{Data}->{Version};
 if($Target ne'awaiting_approval'&&$Q->{Data}->{Status}eq'awaiting_approval'){$Q=$Change->Decide(Subject=>$Subject,TenantID=>$Tenant,UserID=>$UserID,ChangeID=>$ID,ExpectedVersion=>$V,Decision=>'approved',Comment=>'CareOnCloud demo CAB onayi');die"CAB approval failed: $Q->{Error}\n"if!$Q->{Success};$V=$Q->{Data}->{Version}}
 if($Target eq'completed'||$Target eq'implementing'){$Q=$Change->Transition(Subject=>$Subject,TenantID=>$Tenant,UserID=>$UserID,ChangeID=>$ID,ExpectedVersion=>$V,ToStatus=>'implementing');die"Start failed: $Q->{Error}\n"if!$Q->{Success};$V=$Q->{Data}->{Version};if($Target eq'completed'){$Q=$Change->Transition(Subject=>$Subject,TenantID=>$Tenant,UserID=>$UserID,ChangeID=>$ID,ExpectedVersion=>$V,ToStatus=>'completed');die"Complete failed: $Q->{Error}\n"if!$Q->{Success}}}
 elsif($Target eq'cancelled'){$Q=$Change->Transition(Subject=>$Subject,TenantID=>$Tenant,UserID=>$UserID,ChangeID=>$ID,ExpectedVersion=>$V,ToStatus=>'cancelled');die"Cancel failed: $Q->{Error}\n"if!$Q->{Success}}
 $Created++;
}
print"CareOnCloud Change demo seed complete: created=$Created existing=$Existing\n";
