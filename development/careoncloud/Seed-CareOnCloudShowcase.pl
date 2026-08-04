#!/usr/bin/env perl
# --
# CareOnCloud ESM synthetic showcase data. No named organization is a customer reference.
# Copyright (C) 2026 Data Market Bilgi Hizmetleri A.S.
# SPDX-License-Identifier: GPL-3.0-only
# --
use v5.24;
use strict;
use warnings;
use utf8;
use JSON::PP ();
use Kernel::System::ObjectManager;

my $Password = $ENV{CAREONCLOUD_DEMO_PASSWORD} // q{};
die "CAREONCLOUD_DEMO_PASSWORD is required\n" if length($Password) < 12;

local $Kernel::OM = Kernel::System::ObjectManager->new();
my $DB        = $Kernel::OM->Get('Kernel::System::DB');
my $Directory = $Kernel::OM->Get('Kernel::System::CareOnCloud::TenantDirectory');
my $Catalog   = $Kernel::OM->Get('Kernel::System::CareOnCloud::Catalog');
my $Request   = $Kernel::OM->Get('Kernel::System::CareOnCloud::Request');
my $Commitment = $Kernel::OM->Get('Kernel::System::CareOnCloud::Commitment');
my $Company   = $Kernel::OM->Get('Kernel::System::CustomerCompany');
my $Customer  = $Kernel::OM->Get('Kernel::System::CustomerUser');
my $ActorUserID = 47;
my $WriteUserID = 1;
my $Platform = { ID => 'careoncloud-showcase-seeder', Roles => ['platform_admin'], TenantIDs => ['bootstrap'] };
$Kernel::OM->Get('Kernel::Config')->Set( Key => 'CheckEmailAddresses', Value => 0 );
$Kernel::OM->Get('Kernel::Config')->Set( Key => 'CareOnCloud::TenantGuard::AllowPlatformAdmin', Value => 1 );

my @Tenant = (
    {
        ID => 'showcase-bank', Name => 'Marmara Bank Demo', Login => 'bank.demo', First => 'Deniz', Last => 'Bankacılık Demo',
        City => 'İstanbul', Sector => 'Türkiye bankacılık operasyonlarını temsil eden sentetik kuruluş',
        Service => [
            [ 'employee-banking', 'Çalışan Bankacılık Teknolojileri', 'Şube ve genel müdürlük çalışanları için güvenli dijital iş yeri.',
              'secure-access', 'Güvenli Erişim',
              [
                [ 'bank-app-access', 'Kritik Uygulama Erişimi', 'Bankacılık uygulaması için rol bazlı erişim, SoD kontrolü ve yönetici onayı.' ],
                [ 'branch-device', 'Şube Çalışanı Cihazı', 'Şube personeli için yönetilen dizüstü bilgisayar ve güvenlik profili.' ],
              ] ],
        ],
        Locations => [qw(Levent Maslak Ataşehir Kadıköy Bursa Ankara)],
    },
    {
        ID => 'showcase-fashion', Name => 'Anadolu Moda Demo', Login => 'moda.demo', First => 'Ece', Last => 'Moda Demo',
        City => 'İstanbul', Sector => 'Türkiye hazır giyim süreçlerini temsil eden sentetik kuruluş',
        Service => [
            [ 'fashion-operations', 'Moda ve E-Ticaret Operasyonları', 'Koleksiyon, mağaza ve dijital kanal ekipleri için uçtan uca hizmetler.',
              'collection-workplace', 'Koleksiyon Çalışma Alanı',
              [
                [ 'design-workstation', 'Tasarım İş İstasyonu', 'Tasarım ekibi için yüksek performanslı cihaz ve lisans paketi.' ],
                [ 'product-publish', 'E-Ticaret Ürün Yayını', 'Ürün içeriği, görsel kalite ve kanal yayın kontrolü.' ],
              ] ],
        ],
        Locations => [qw(Merter Zeytinburnu Bayrampaşa İzmir Bursa Ankara)],
    },
    {
        ID => 'showcase-retail', Name => 'Perakende360 Demo', Login => 'retail.demo', First => 'Mert', Last => 'Perakende Demo',
        City => 'İstanbul', Sector => 'Türkiye çok mağazalı perakende süreçlerini temsil eden sentetik kuruluş',
        Service => [
            [ 'store-technology', 'Mağaza Teknolojileri', 'Mağaza açılışı, POS, ağ ve saha operasyonlarının tek hizmet modeli.',
              'store-operations', 'Mağaza Operasyonları',
              [
                [ 'pos-incident', 'POS Arızası ve Değişimi', 'Satış sürekliliği için öncelikli POS tanılama ve cihaz değişimi.' ],
                [ 'new-store-opening', 'Yeni Mağaza Açılışı', 'Ağ, POS, kullanıcı, cihaz ve saha kontrol listesiyle mağaza devreye alma.' ],
              ] ],
        ],
        Locations => [qw(İstinye Emaar Akasya İzmir Bursa Ankara)],
    },
);

sub Must {
    my ( $Result, $Message ) = @_;
    die "$Message: " . ( $Result->{Error} // 'UNKNOWN' ) . ( $Result->{Reason} ? " ($Result->{Reason})" : q{} ) . "\n" if !$Result->{Success};
    return $Result->{Data};
}

sub TenantExists {
    my ($ID) = @_;
    $DB->Prepare( SQL => 'SELECT 1 FROM careoncloud_tenant WHERE key_name = ?', Bind => [ \$ID ], Limit => 1 );
    my ($Exists) = $DB->FetchrowArray();
    return $Exists ? 1 : 0;
}

sub CompanyEnsure {
    my ($T) = @_;
    my %Existing = $Company->CustomerCompanyGet( CustomerID => $T->{ID} );
    return if %Existing;
    my $OK = $Company->CustomerCompanyAdd(
        CustomerID => $T->{ID}, CustomerCompanyName => $T->{Name},
        CustomerCompanyStreet => 'Sentetik satış demosu — gerçek müşteri değildir',
        CustomerCompanyZIP => '34000', CustomerCompanyCity => $T->{City},
        CustomerCompanyCountry => 'Türkiye', CustomerCompanyURL => 'https://esm.arcak.net',
        CustomerCompanyComment => "$T->{Sector}. CareOnCloud ESM showcase verisidir; müşteri referansı değildir.",
        ValidID => 1, UserID => $WriteUserID,
    );
    die "customer company create failed for $T->{ID}\n" if !$OK;
}

sub CustomerEnsure {
    my ($T) = @_;
    my %Existing = $Customer->CustomerUserDataGet( User => $T->{Login} );
    if (!%Existing) {
        my $OK = $Customer->CustomerUserAdd(
            Source => 'CustomerUser', UserFirstname => $T->{First}, UserLastname => $T->{Last},
            UserCustomerID => $T->{ID}, UserLogin => $T->{Login},
            UserEmail => "$T->{Login}\@demo.careoncloud.invalid", ValidID => 1, UserID => $WriteUserID,
        );
        die "customer create failed for $T->{Login}\n" if !$OK;
    }
    die "password set failed for $T->{Login}\n" if !$Customer->SetPassword( UserLogin => $T->{Login}, PW => $Password );
}

sub MembershipsEnsure {
    my ($TenantID) = @_;
    for my $Role (qw(tenant_admin agent service_owner auditor)) {
        Must(
            $Directory->MembershipGrant(
                Subject => $Platform, TenantID => $TenantID, MemberUserID => $ActorUserID,
                Role => $Role, UserID => $WriteUserID,
            ),
            "membership $TenantID/$Role",
        );
    }
}

sub PolicyEnsure {
    my ($TenantID) = @_;
    my $Policies = $Commitment->PolicyList( Subject => $Platform, TenantID => $TenantID );
    Must( $Policies, "policy list $TenantID" );
    return if grep { $_->{Key} eq 'showcase-standard' } @{ $Policies->{Data} };
    Must(
        $Commitment->PolicyCreate(
            Subject => $Platform, TenantID => $TenantID, UserID => $WriteUserID,
            Key => 'showcase-standard', Name => 'CareOnCloud Showcase Standard', CalendarID => 0,
            TargetSeconds => 28_800, WarningPercent => 75, PauseStatuses => ['awaiting_approval'], Status => 'active',
            Objectives => [
                { key => 'first-response', type => 'response', target_seconds => 3600, warning_percent => 75, start_signal => 'request_created', stop_signal => 'first_response', escalation_actions => [] },
                { key => 'resolution', type => 'resolution', target_seconds => 28_800, warning_percent => 75, start_signal => 'request_created', stop_signal => 'request_fulfilled', escalation_actions => [] },
                { key => 'internal-ola', type => 'ola', target_seconds => 14_400, warning_percent => 75, start_signal => 'request_approved', stop_signal => 'request_fulfilled', escalation_actions => [] },
            ],
        ),
        "policy create $TenantID",
    );
}

sub CatalogEnsure {
    my ($T) = @_;
    my @Items;
    for my $Definition ( @{ $T->{Service} } ) {
        my ( $ServiceKey, $ServiceName, $ServiceDescription, $OfferingKey, $OfferingName, $ItemDefinitions ) = @{$Definition};
        my $Services = $Catalog->ServiceList( Subject => $Platform, TenantID => $T->{ID} );
        Must( $Services, "service list $T->{ID}" );
        my ($Service) = grep { $_->{Key} eq $ServiceKey } @{ $Services->{Data} };
        $Service //= Must(
            $Catalog->ServiceCreate(
                Subject => $Platform, TenantID => $T->{ID}, UserID => $WriteUserID,
                Key => $ServiceKey, Name => $ServiceName, Description => $ServiceDescription, Status => 'active',
            ), "service create $T->{ID}/$ServiceKey",
        );
        my $Offerings = $Catalog->OfferingList(
            Subject => $Platform, TenantID => $T->{ID}, ServiceID => $Service->{ServiceID},
        );
        Must( $Offerings, "offering list $T->{ID}" );
        my ($Offering) = grep { $_->{Key} eq $OfferingKey } @{ $Offerings->{Data} };
        $Offering //= Must(
            $Catalog->OfferingCreate(
                Subject => $Platform, TenantID => $T->{ID}, UserID => $WriteUserID,
                ServiceID => $Service->{ServiceID}, Key => $OfferingKey, Name => $OfferingName,
                Description => "$OfferingName için sentetik showcase hizmet sunumu.", Status => 'active', FulfillmentType => 'process',
            ), "offering create $T->{ID}/$OfferingKey",
        );
        for my $ItemDefinition ( @{$ItemDefinitions} ) {
            my ( $Key, $Name, $Description ) = @{$ItemDefinition};
            my $Items = $Catalog->CatalogItemList(
                Subject => $Platform, TenantID => $T->{ID}, OfferingID => $Offering->{OfferingID},
            );
            Must( $Items, "item list $T->{ID}" );
            my ($Item) = grep { $_->{Key} eq $Key } @{ $Items->{Data} };
            $Item //= Must(
                $Catalog->CatalogItemCreate(
                    Subject => $Platform, TenantID => $T->{ID}, UserID => $WriteUserID,
                    OfferingID => $Offering->{OfferingID}, Key => $Key, Name => $Name,
                    Description => $Description, Status => 'active', RequestType => 'service_request',
                ), "item create $T->{ID}/$Key",
            );
            my $Schema = $Catalog->CatalogItemSchemaGet(
                Subject => $Platform, TenantID => $T->{ID}, CatalogItemID => $Item->{CatalogItemID},
            );
            if (!$Schema->{Success}) {
                Must(
                    $Catalog->CatalogItemSchemaSet(
                        Subject => $Platform, TenantID => $T->{ID}, UserID => $WriteUserID,
                        CatalogItemID => $Item->{CatalogItemID}, Schema => {
                            version => 1,
                            workflow => {
                                approval => { required => 1, approver_role => 'tenant_admin' },
                                fulfillment => [ { key => 'fulfill', name => "$Name — uygulama ve doğrulama", type => 'manual' } ],
                                commitment => { default_policy_key => 'showcase-standard', entitlements => [] },
                            },
                            fields => [
                                { key => 'location', label => 'Lokasyon', type => 'text', required => 1 },
                                { key => 'urgency', label => 'Aciliyet', type => 'select', required => 1, options => [
                                    { value => 'normal', label => 'Normal' }, { value => 'high', label => 'Yüksek' },
                                ] },
                                { key => 'details', label => 'İş ihtiyacı ve ayrıntılar', type => 'textarea', required => 1 },
                            ],
                        },
                    ), "schema create $T->{ID}/$Key",
                );
            }
            push @Items, $Item;
        }
    }
    return \@Items;
}

sub RequestSeed {
    my ( $T, $Items ) = @_;
    my @State = qw(fulfilled fulfilled fulfilled fulfilled fulfilled awaiting_approval awaiting_approval in_fulfillment in_fulfillment rejected fulfillment_failed fulfilled);
    my $Created = 0;
    for my $Index ( 0 .. $#State ) {
        my $Item = $Items->[ $Index % @{$Items} ];
        my $Location = $T->{Locations}->[ $Index % @{ $T->{Locations} } ];
        my $Submission = $Request->CustomerSubmit(
            CustomerUserID => $T->{Login}, CustomerID => $T->{ID}, CatalogItemID => $Item->{CatalogItemID},
            IdempotencyKey => sprintf( 'careoncloud-showcase-%s-%02d', $T->{ID}, $Index + 1 ),
            Answers => {
                location => $Location, urgency => $Index % 4 == 0 ? 'high' : 'normal',
                details => "Sentetik demo talebi #" . ( $Index + 1 ) . " — $Location operasyonu için $Item->{Name}.",
            },
        );
        my $Aggregate = Must( $Submission, "request submit $T->{ID}/$Index" );
        $Created++ if !$Submission->{IdempotentReplay};
        next if $State[$Index] eq 'awaiting_approval';
        if ( $Aggregate->{Status} eq 'awaiting_approval' ) {
            my $Decision = $State[$Index] eq 'rejected' ? 'rejected' : 'approved';
            $Aggregate = Must(
                $Request->ApprovalDecide(
                    UserID => $ActorUserID, TenantID => $T->{ID}, RequestID => $Aggregate->{RequestID},
                    Decision => $Decision, ExpectedVersion => $Aggregate->{Approvals}->[0]->{Version},
                    Comment => $Decision eq 'approved' ? 'Sentetik showcase onayı verildi.' : 'Sentetik bütçe senaryosu nedeniyle reddedildi.',
                ), "approval $T->{ID}/$Index",
            );
        }
        next if $State[$Index] eq 'rejected';
        if ( $Aggregate->{Status} eq 'in_fulfillment' ) {
            my $Response = $Request->ResponseRecord(
                UserID => $ActorUserID, TenantID => $T->{ID}, RequestID => $Aggregate->{RequestID},
            );
            die "first response failed $T->{ID}/$Index: $Response->{Error}\n"
                if !$Response->{Success} && ( $Response->{Error} // q{} ) ne 'TRANSITION_INVALID';
        }
        next if $State[$Index] eq 'in_fulfillment';
        my ($Task) = grep { $_->{Status} =~ m{\A(?:pending|in_progress)\z} } @{ $Aggregate->{Tasks} };
        next if !$Task;
        my $TaskStatus = $State[$Index] eq 'fulfillment_failed' ? 'failed' : 'completed';
        Must(
            $Request->TaskUpdate(
                UserID => $ActorUserID, TenantID => $T->{ID}, TaskID => $Task->{TaskID},
                Status => $TaskStatus, ExpectedVersion => $Task->{Version},
                Comment => $TaskStatus eq 'completed' ? 'Showcase görevi başarıyla tamamlandı.' : 'Sentetik tedarik gecikmesi kaydedildi.',
            ), "task $T->{ID}/$Index",
        );
    }
    return $Created;
}

my @Summary;
for my $T (@Tenant) {
    if ( !TenantExists( $T->{ID} ) ) {
        Must(
            $Directory->TenantCreate(
                Subject => $Platform, TenantID => $T->{ID}, Name => $T->{Name}, Status => 'active', UserID => $WriteUserID,
            ), "tenant create $T->{ID}",
        );
    }
    CompanyEnsure($T);
    CustomerEnsure($T);
    MembershipsEnsure( $T->{ID} );
    PolicyEnsure( $T->{ID} );
    my $Items = CatalogEnsure($T);
    my $NewRequests = RequestSeed( $T, $Items );
    $DB->Prepare( SQL => 'SELECT status, COUNT(*) FROM careoncloud_request WHERE tenant_id = ? GROUP BY status ORDER BY status', Bind => [ \$T->{ID} ] );
    my %Status;
    while ( my ( $Name, $Count ) = $DB->FetchrowArray() ) { $Status{$Name} = 0 + $Count }
    push @Summary, {
        tenant_id => $T->{ID}, tenant_name => $T->{Name}, login => $T->{Login},
        catalog_items => scalar @{$Items}, new_requests => $NewRequests, request_status => \%Status,
        synthetic => JSON::PP::true,
    };
}

say JSON::PP->new->canonical->pretty->encode({ success => JSON::PP::true, product => 'CareOnCloud ESM', tenants => \@Summary });
