package Kernel::Language::tr_D724Assist;
use strict;
use warnings;
use utf8;
sub Data {
    my $Self = shift;
    my %Translation = (
        'Agent Assistant' => 'Destek Asistanı',
        'Explainable similar-case recommendations.' => 'Açıklanabilir benzer vaka önerileri.',
        'Find similar resolved requests without sending tenant data externally.' => 'Tenant verilerini dışarı göndermeden benzer sonuçlanmış talepleri bulun.',
    );
    $Self->{Translation}->{$_} = $Translation{$_} for keys %Translation;
    return;
}
1;
