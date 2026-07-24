# --
# D724 ESM is an enterprise service management platform based on OTOBO.
# Copyright (C) 2026 Data Market Bilgi Hizmetleri A.S.
# SPDX-License-Identifier: GPL-3.0-only
# --

package Kernel::System::D724::CatalogPortal;

use v5.24;
use strict;
use warnings;

use Digest::SHA qw(sha256_hex);

our $VERSION = '0.3.2';
our @ObjectDependencies = ('Kernel::System::D724::Catalog');

sub new {
    my ($Type) = @_;
    return bless {}, $Type;
}

sub ContextGet {
    my ( $Self, %Param ) = @_;
    return $Self->_ContextGet(%Param);
}

sub CatalogGet {
    my ( $Self, %Param ) = @_;
    my $Context = $Self->_ContextGet(%Param);
    return $Context if !$Context->{Success};
    my $Catalog = $Kernel::OM->Get('Kernel::System::D724::Catalog');
    my $Services = $Catalog->ServiceList(
        Subject => $Context->{Subject}, TenantID => $Context->{TenantID}, Status => 'active',
    );
    return $Services if !$Services->{Success};
    for my $Service ( @{ $Services->{Data} } ) {
        my $Offerings = $Catalog->OfferingList(
            Subject => $Context->{Subject}, TenantID => $Context->{TenantID},
            ServiceID => $Service->{ServiceID}, Status => 'active',
        );
        return $Offerings if !$Offerings->{Success};
        $Service->{Offerings} = $Offerings->{Data};
        for my $Offering ( @{ $Service->{Offerings} } ) {
            my $Items = $Catalog->CatalogItemList(
                Subject => $Context->{Subject}, TenantID => $Context->{TenantID},
                OfferingID => $Offering->{OfferingID}, Status => 'active',
            );
            return $Items if !$Items->{Success};
            $Offering->{Items} = $Items->{Data};
        }
    }
    return { Success => 1, Data => $Services->{Data}, TenantID => $Context->{TenantID} };
}

sub ItemGet {
    my ( $Self, %Param ) = @_;
    my $Context = $Self->_ContextGet(%Param);
    return $Context if !$Context->{Success};
    my $Catalog = $Kernel::OM->Get('Kernel::System::D724::Catalog');
    my $Item = $Catalog->CatalogItemGet(
        Subject => $Context->{Subject}, TenantID => $Context->{TenantID},
        CatalogItemID => $Param{CatalogItemID},
    );
    return $Item if !$Item->{Success};
    return { Success => 0, Error => 'NOT_AVAILABLE' } if $Item->{Data}->{Status} ne 'active';
    my $Offering = $Catalog->OfferingGet(
        Subject => $Context->{Subject}, TenantID => $Context->{TenantID},
        OfferingID => $Item->{Data}->{OfferingID},
    );
    return $Offering if !$Offering->{Success};
    return { Success => 0, Error => 'NOT_AVAILABLE' } if $Offering->{Data}->{Status} ne 'active';
    my $Service = $Catalog->ServiceGet(
        Subject => $Context->{Subject}, TenantID => $Context->{TenantID},
        ServiceID => $Offering->{Data}->{ServiceID},
    );
    return $Service if !$Service->{Success};
    return { Success => 0, Error => 'NOT_AVAILABLE' } if $Service->{Data}->{Status} ne 'active';
    my $Schema = $Catalog->CatalogItemSchemaGet(
        Subject => $Context->{Subject}, TenantID => $Context->{TenantID},
        CatalogItemID => $Param{CatalogItemID},
    );
    return $Schema if !$Schema->{Success};
    $Item->{Data}->{FormSchema} = $Schema->{Data};
    return $Item;
}

sub _ContextGet {
    my ( $Self, %Param ) = @_;
    return { Success => 0, Error => 'CUSTOMER_USER_MISSING' }
        if !defined $Param{CustomerUserID} || !length $Param{CustomerUserID};
    return { Success => 0, Error => 'CUSTOMER_TENANT_MISSING' }
        if !defined $Param{CustomerID} || !length $Param{CustomerID};
    return {
        Success  => 1,
        TenantID => $Param{CustomerID},
        Subject  => {
            ID        => 'customer:' . sha256_hex( $Param{CustomerUserID} ),
            Roles     => ['requester'],
            TenantIDs => [ $Param{CustomerID} ],
        },
    };
}

1;
