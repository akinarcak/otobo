package Kernel::Language::tr_D724CMDB;
use strict;
use warnings;
use utf8;
sub Data {
    my $Self = shift;
    my %Translation = (
        'Service Portfolio' => 'Hizmet Portföyü',
        'Browse tenant-scoped service portfolio.' => 'Tenant kapsamındaki hizmet portföyünü görüntüleyin.',
        'Browse customer services, instances, ownership and criticality.' => 'Müşteri hizmetlerini, örneklerini, sahipliğini ve kritikliğini görüntüleyin.',
    );
    $Self->{Translation}->{$_} = $Translation{$_} for keys %Translation;
    return;
}
1;
