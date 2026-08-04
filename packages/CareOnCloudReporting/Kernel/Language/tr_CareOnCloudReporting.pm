# --
# CareOnCloud ESM enterprise service management platform.
# Copyright (C) 2026 Data Market Bilgi Hizmetleri A.S.
# SPDX-License-Identifier: GPL-3.0-only
# --
package Kernel::Language::tr_CareOnCloudReporting;

use strict;
use warnings;
use utf8;

sub Data {
    my $Self = shift;
    my %Translation = (
        'CareOnCloud Operations Center' => 'CareOnCloud Operasyon Merkezi',
        'Operations Center'             => 'Operasyon Merkezi',
        'Report scope'                  => 'Rapor kapsamı',
        'Custom report designer'        => 'Özelleştirilebilir rapor tasarımcısı',
        'Customer'                      => 'Müşteri',
        'Please select'                 => 'Lütfen seçin',
        'From'                          => 'Başlangıç',
        'To'                            => 'Bitiş',
        'Refresh'                       => 'Yenile',
        'Group by'                      => 'Gruplama boyutları',
        'Metrics'                       => 'Ölçümler',
        'Status filter'                 => 'Durum filtresi',
        'Run report'                    => 'Raporu çalıştır',
        'Export custom report'          => 'Özel raporu dışa aktar',
        'Saved reports'                 => 'Kaydedilmiş raporlar',
        'Load report'                   => 'Raporu yükle',
        'Save report definition'        => 'Rapor tanımını kaydet',
        'Technical key'                 => 'Teknik anahtar',
        'Report name'                   => 'Rapor adı',
        'Description'                   => 'Açıklama',
        'Visibility'                    => 'Görünürlük',
        'private'                       => 'özel',
        'shared'                        => 'paylaşılan',
        'Save report'                   => 'Raporu kaydet',
        'Report definition saved.'      => 'Rapor tanımı kaydedildi.',
        'Requests'                      => 'Talepler',
        'SLA objectives'                => 'SLA hedefleri',
        'Breaches'                      => 'İhlaller',
        'SLA compliance'                => 'SLA uyumu',
        'Request status'                => 'Talep durumu',
        'Status'                        => 'Durum',
        'Count'                         => 'Adet',
        'Demand by catalog item'        => 'Katalog kalemine göre talep',
        'Catalog item'                  => 'Katalog kalemi',
        'SLA health'                    => 'SLA sağlığı',
        'Objective'                     => 'Hedef',
        'Service category'              => 'Hizmet kategorisi',
        'Service extension'             => 'Servis uzantısı',
        'Request type'                  => 'Talep türü',
        'Month'                         => 'Ay',
    );
    $Self->{Translation}->{$_} = $Translation{$_} for keys %Translation;
    return;
}

1;
