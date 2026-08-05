package Kernel::Language::tr_CareOnCloudCommitment;
use strict;
use warnings;
use utf8;
sub Data {
    my $Self = shift;
    my %Translation = ('CareOnCloud Commitments' => 'CareOnCloud Taahhütleri','Commitment' => 'Taahhüt','Response' => 'Yanıt','Resolution' => 'Çözüm','Warning' => 'Uyarı','Breach' => 'İhlal');
    $Self->{Translation}->{$_} = $Translation{$_} for keys %Translation;
    return;
}
1;
