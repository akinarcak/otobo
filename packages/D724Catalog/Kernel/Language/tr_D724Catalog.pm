# --
# CareOnCloud ESM enterprise service management platform.
# Copyright (C) 2026 Data Market Bilgi Hizmetleri A.S.
# SPDX-License-Identifier: GPL-3.0-only
# --
package Kernel::Language::tr_D724Catalog;

use strict;
use warnings;
use utf8;

sub Data {
    my $Self = shift;
    $Self->{Translation}->{'Service Catalog'} = 'Hizmet Kataloğu';
    $Self->{Translation}->{'Create a service request'} = 'Hizmet talebi oluştur';
    $Self->{Translation}->{'Select the service category, service extension and request type.'} = 'Hizmet kategorisini, servis uzantısını ve talep türünü seçin.';
    $Self->{Translation}->{'Service category'} = 'Hizmet kategorisi';
    $Self->{Translation}->{'Service extension'} = 'Servis uzantısı';
    $Self->{Translation}->{'Request type'} = 'Talep türü';
    $Self->{Translation}->{'Selected service'} = 'Seçilen hizmet';
    $Self->{Translation}->{'Please select'} = 'Lütfen seçin';
    $Self->{Translation}->{'Continue'} = 'Devam et';
    $Self->{Translation}->{'Open request form'} = 'Talep formunu aç';
    $Self->{Translation}->{'Submit request'} = 'Talebi gönder';
    return;
}

1;
