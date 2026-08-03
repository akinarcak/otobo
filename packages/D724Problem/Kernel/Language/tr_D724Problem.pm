package Kernel::Language::tr_D724Problem;
use strict;
use warnings;
use utf8;
sub Data {
    my $Self = shift;
    my %Translation = ('Problem Management' => 'Problem Yönetimi','Manage root cause and known errors.' => 'Kök nedenleri ve bilinen hataları yönetin.','Investigate root causes, publish workarounds and control permanent fixes.' => 'Kök nedenleri araştırın, geçici çözümler yayınlayın ve kalıcı düzeltmeleri yönetin.');
    $Self->{Translation}->{$_} = $Translation{$_} for keys %Translation;
    return;
}
1;
