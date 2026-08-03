package Kernel::Language::tr_D724Commitment;
use strict;
use warnings;
use utf8;
sub Data {
    my $Self = shift;
    my %Translation = ('D724 Commitments' => 'CareOnCloud Taahhütleri','Commitment' => 'Taahhüt','Response' => 'Yanıt','Resolution' => 'Çözüm','Warning' => 'Uyarı','Breach' => 'İhlal');
    $Self->{Translation}->{$_} = $Translation{$_} for keys %Translation;
    return;
}
1;
