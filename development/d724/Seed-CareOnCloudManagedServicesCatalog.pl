#!/usr/bin/env perl
# --
# CareOnCloud managed services catalog, based on DD-YHE-02-R1.
# Copyright (C) 2026 Data Market Bilgi Hizmetleri A.S.
# SPDX-License-Identifier: GPL-3.0-only
# --
use v5.24;
use strict;
use warnings;
use utf8;
use Kernel::System::ObjectManager;

local $Kernel::OM = Kernel::System::ObjectManager->new();
my $Catalog = $Kernel::OM->Get('Kernel::System::D724::Catalog');
my $DB      = $Kernel::OM->Get('Kernel::System::DB');
my $ActorID = 1;
my $Subject = { ID => 'careoncloud-catalog-importer', Roles => ['platform_admin'], TenantIDs => ['bootstrap'] };
$Kernel::OM->Get('Kernel::Config')->Set( Key => 'D724::TenantGuard::AllowPlatformAdmin', Value => 1 );

my @Tenant = @ARGV ? @ARGV : qw(d724-demo showcase-bank showcase-fashion showcase-retail);
my @Category = (
    [ 'monitoring-visibility', 'İzleme ve Görünürlük', 'DORA ICT risk yönetimi ve operasyonel dayanıklılık için merkezi izleme.', [
        [ 'infrastructure-monitoring', 'Altyapı İzleme' ],
        [ 'application-monitoring', 'Uygulama İzleme' ],
        [ 'network-monitoring', 'Ağ İzleme' ],
        [ 'log-monitoring', 'Log İzleme ve Korelasyon' ],
        [ 'capacity-availability', 'Kapasite ve Kullanılabilirlik İzleme' ],
    ] ],
    [ 'system-infrastructure', 'Sistem ve Altyapı Yönetimi', 'Sunucu, veri, kimlik, iş sürekliliği ve kurumsal altyapı işletimi.', [
        [ 'operational-service-management', 'Operasyonel Hizmet Yönetimi' ],
        [ 'server-os-management', 'Sunucu İşletim Sistemi Yönetimi' ],
        [ 'identity-directory', 'Kimlik ve Dizin Servisleri Yönetimi' ],
        [ 'enterprise-email-server', 'Kurumsal E-posta Sunucusu Yönetimi' ],
        [ 'file-sharing', 'Dosya ve Paylaşım Servisleri Yönetimi' ],
        [ 'remote-access-session', 'Uzak Erişim ve Oturum Yönetimi' ],
        [ 'web-server', 'Web Sunucusu Yönetimi' ],
        [ 'database-platforms', 'Veritabanı Platformları Yönetimi' ],
        [ 'virtualization', 'Sanallaştırma Platformu Yönetimi' ],
        [ 'hci', 'Hiper Bütünleşik Altyapı Yönetimi' ],
        [ 'dr-replication', 'Felaket Kurtarma ve Replikasyon Yönetimi' ],
        [ 'storage', 'Depolama Sistemleri Yönetimi' ],
        [ 'backup-restore', 'Yedekleme ve Geri Dönüş Yönetimi' ],
        [ 'microsoft-sccm', 'Microsoft SCCM Yönetimi' ],
    ] ],
    [ 'cloud-platform', 'Bulut ve Platform Yönetimi', 'Bulut servisleri, modern platformlar, otomasyon ve DevOps işletimi.', [
        [ 'cloud-operations', 'Bulut Operasyonel Hizmet Yönetimi' ],
        [ 'saas-tenant-identity', 'SaaS Tenant ve Kimlik Yönetimi' ],
        [ 'cloud-email', 'Bulut E-posta Yönetimi' ],
        [ 'cloud-collaboration', 'Bulut İş Birliği Platformları Yönetimi' ],
        [ 'cloud-file-sharing', 'Bulut Dosya ve Paylaşım Yönetimi' ],
        [ 'cloud-endpoint', 'Bulut Uç Nokta Yönetimi' ],
        [ 'azure-infrastructure', 'Azure Altyapı Yönetimi' ],
        [ 'azure-policy-compliance', 'Azure Politika ve Uyumluluk Yönetimi' ],
        [ 'azure-finops', 'Azure Maliyet ve FinOps Yönetimi' ],
        [ 'container-platform', 'Konteyner Platformu Yönetimi' ],
        [ 'audit-log-infrastructure', 'Log Toplama ve Denetim Altyapısı' ],
        [ 'automation', 'Otomasyon Yönetimi' ],
        [ 'devops-pipeline', 'DevOps Pipeline Yönetimi' ],
    ] ],
    [ 'network-infrastructure', 'Ağ ve Ağ Güvenliği', 'Kurumsal bağlantı, erişim ve ağ güvenliği servislerinin işletimi.', [
        [ 'network-security-operations', 'Ağ ve Ağ Güvenliği Yönetimi' ],
        [ 'firewall', 'Güvenlik Duvarı Yönetimi' ],
        [ 'switching', 'Anahtarlama Altyapısı Yönetimi' ],
        [ 'wireless', 'Kablosuz Ağ Yönetimi' ],
        [ 'nac', 'Ağ Erişim Kontrolü Yönetimi' ],
    ] ],
    [ 'cybersecurity', 'Siber Güvenlik Yönetimi', 'Tehdit önleme, tespit, müdahale ve DORA uyum kontrolleri.', [
        [ 'authentication-security', 'Kimlik Doğrulama Güvenliği' ],
        [ 'web-application-security', 'Web Uygulama Güvenliği' ],
        [ 'security-log-analysis', 'Güvenlik Log ve Analiz Yönetimi' ],
        [ 'dlp', 'Veri Kaybı Önleme Yönetimi' ],
        [ 'email-security', 'E-posta Güvenliği Yönetimi' ],
        [ 'endpoint-security', 'Uç Nokta Güvenliği Yönetimi' ],
        [ 'server-workload-security', 'Sunucu İş Yükü Güvenliği' ],
        [ 'microsoft-siem-incident', 'Microsoft SIEM ve Güvenlik Olayı Yönetimi' ],
        [ 'microsoft-soc-monitoring', 'Microsoft SOC İzleme ve Alarm Yönetimi' ],
        [ 'microsoft-xdr', 'Microsoft XDR Yönetimi' ],
        [ 'security-incident-response', 'Güvenlik Olayı Müdahale ve Eskalasyon' ],
        [ 'cloud-security', 'Bulut Güvenliği Yönetimi' ],
        [ 'cloud-compliance-data-protection', 'Bulut Uyumluluk ve Veri Koruma' ],
    ] ],
    [ 'professional-services', 'Profesyonel Hizmetler', 'Dönüşüm, mimari, uyumluluk ve teknoloji danışmanlığı.', [
        [ 'consulting', 'Danışmanlık Hizmetleri' ],
    ] ],
);

sub Must {
    my ( $Result, $Message ) = @_;
    die "$Message: " . ( $Result->{Error} // 'UNKNOWN' ) . "\n" if !$Result->{Success};
    return $Result->{Data};
}

sub TenantExists {
    my ($TenantID) = @_;
    $DB->Prepare( SQL => 'SELECT 1 FROM d724_tenant WHERE key_name = ?', Bind => [ \$TenantID ], Limit => 1 );
    my ($Exists) = $DB->FetchrowArray();
    return $Exists ? 1 : 0;
}

my ( $TenantCount, $ItemCount ) = ( 0, 0 );
for my $TenantID (@Tenant) {
    if ( !TenantExists($TenantID) ) {
        warn "Tenant bulunamadı, atlandı: $TenantID\n";
        next;
    }
    for my $Category (@Category) {
        my ( $CategoryKey, $CategoryName, $CategoryDescription, $Offerings ) = @{$Category};
        my $Services = Must( $Catalog->ServiceList( Subject => $Subject, TenantID => $TenantID ), "service list $TenantID" );
        my ($Service) = grep { $_->{Key} eq $CategoryKey } @{$Services};
        $Service //= Must( $Catalog->ServiceCreate(
            Subject => $Subject, TenantID => $TenantID, UserID => $ActorID,
            Key => $CategoryKey, Name => $CategoryName,
            Description => "$CategoryDescription Kaynak: Careon Hizmet Kataloğu DD-YHE-02-R1.", Status => 'active',
        ), "service create $TenantID/$CategoryKey" );

        for my $Definition (@{$Offerings}) {
            my ( $Key, $Name ) = @{$Definition};
            my $ExistingOfferings = Must( $Catalog->OfferingList(
                Subject => $Subject, TenantID => $TenantID, ServiceID => $Service->{ServiceID},
            ), "offering list $TenantID/$CategoryKey" );
            my ($Offering) = grep { $_->{Key} eq $Key } @{$ExistingOfferings};
            $Offering //= Must( $Catalog->OfferingCreate(
                Subject => $Subject, TenantID => $TenantID, UserID => $ActorID,
                ServiceID => $Service->{ServiceID}, Key => $Key, Name => $Name,
                Description => "$Name kapsamındaki standart, değişiklik ve destek talepleri.",
                Status => 'active', FulfillmentType => 'process',
            ), "offering create $TenantID/$Key" );

            my $ItemKey = "$Key-request";
            my $Items = Must( $Catalog->CatalogItemList(
                Subject => $Subject, TenantID => $TenantID, OfferingID => $Offering->{OfferingID},
            ), "item list $TenantID/$Key" );
            my ($Item) = grep { $_->{Key} eq $ItemKey } @{$Items};
            $Item //= Must( $Catalog->CatalogItemCreate(
                Subject => $Subject, TenantID => $TenantID, UserID => $ActorID,
                OfferingID => $Offering->{OfferingID}, Key => $ItemKey,
                Name => "$Name Talebi",
                Description => "DORA izlenebilirliği ile $Name için hizmet, değişiklik veya destek talebi oluşturun.",
                Status => 'active', RequestType => 'service_request',
            ), "item create $TenantID/$ItemKey" );

            my $Schema = $Catalog->CatalogItemSchemaGet(
                Subject => $Subject, TenantID => $TenantID, CatalogItemID => $Item->{CatalogItemID},
            );
            if ( !$Schema->{Success} ) {
                Must( $Catalog->CatalogItemSchemaSet(
                    Subject => $Subject, TenantID => $TenantID, UserID => $ActorID,
                    CatalogItemID => $Item->{CatalogItemID}, Schema => {
                        version => 1,
                        workflow => {
                            approval => { required => 1, approver_role => 'tenant_admin' },
                            fulfillment => [ { key => 'assess', name => 'Kapsam ve risk değerlendirmesi', type => 'manual' }, { key => 'fulfill', name => 'Uygulama ve doğrulama', type => 'manual' } ],
                            commitment => { default_policy_key => 'showcase-standard', entitlements => [] },
                        },
                        fields => [
                            { key => 'request_kind', label => 'Talep türü', type => 'select', required => 1, options => [
                                { value => 'service', label => 'Hizmet talebi' }, { value => 'change', label => 'Değişiklik talebi' }, { value => 'support', label => 'Destek talebi' },
                            ] },
                            { key => 'criticality', label => 'İş kritikliği', type => 'select', required => 1, options => [
                                { value => 'standard', label => 'Standart' }, { value => 'high', label => 'Yüksek' }, { value => 'critical', label => 'Kritik' },
                            ] },
                            { key => 'affected_asset', label => 'Etkilenen sistem / varlık', type => 'text', required => 1 },
                            { key => 'business_impact', label => 'İş etkisi ve gerekçe', type => 'textarea', required => 1 },
                            { key => 'requested_date', label => 'Talep edilen tamamlanma tarihi', type => 'date', required => 0 },
                            { key => 'dora_trace', label => 'DORA / denetim referansı', type => 'text', required => 0 },
                        ],
                    },
                ), "schema create $TenantID/$ItemKey" );
            }
            $ItemCount++;
        }
    }
    $TenantCount++;
}

print "CareOnCloud managed services catalog ready: tenants=$TenantCount catalog_items=$ItemCount source=DD-YHE-02-R1\n";
