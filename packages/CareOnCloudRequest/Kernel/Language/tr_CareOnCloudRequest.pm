# --
# CareOnCloud ESM enterprise service management platform.
# Copyright (C) 2026 Data Market Bilgi Hizmetleri A.S.
# SPDX-License-Identifier: GPL-3.0-only
# --
package Kernel::Language::tr_CareOnCloudRequest;

use strict;
use warnings;
use utf8;

sub Data {
    my $Self = shift;
    my %Translation = (
        'CareOnCloud Requests' => 'CareOnCloud Talepleri',
        'Submit and view tenant-safe CareOnCloud requests.' => 'Tenant güvenli CareOnCloud taleplerini gönderin ve görüntüleyin.',
        'Request' => 'Talep',
        'Approval' => 'Onay',
        'Task' => 'Görev',
        'Response' => 'Yanıt',
        'Fulfillment' => 'Gerçekleştirme',
    );
    $Self->{Translation}->{$_} = $Translation{$_} for keys %Translation;
    return;
}

1;
