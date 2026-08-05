package Kernel::Language::tr_CareOnCloudChange;
use strict;
use warnings;
use utf8;
sub Data {
    my $Self = shift;
    my %Translation = (
        'Change Enablement' => 'Değişiklik Yönetimi',
        'Manage changes, risk and CAB decisions.' => 'Değişiklikleri, riskleri ve CAB kararlarını yönetin.',
        'Register, assess, approve and execute tenant changes.' => 'Tenant değişikliklerini kaydedin, değerlendirin, onaylayın ve uygulayın.',
    );
    $Self->{Translation}->{$_} = $Translation{$_} for keys %Translation;
    return;
}
1;
