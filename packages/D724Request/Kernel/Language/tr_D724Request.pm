# --
# CareOnCloud ESM enterprise service management platform.
# Copyright (C) 2026 Data Market Bilgi Hizmetleri A.S.
# SPDX-License-Identifier: GPL-3.0-only
# --
package Kernel::Language::tr_D724Request;

use strict;
use warnings;
use utf8;

sub Data {
    my $Self = shift;
    my %Translation = (
        'D724 Requests' => 'CareOnCloud Talepleri',
        'Submit and view tenant-safe D724 requests.' => 'Tenant güvenli CareOnCloud taleplerini gönderin ve görüntüleyin.',
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
