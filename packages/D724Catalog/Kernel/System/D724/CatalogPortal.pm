# --
# D724 ESM is an enterprise service management platform based on OTOBO.
# Copyright (C) 2026 Data Market Bilgi Hizmetleri A.S.
# SPDX-License-Identifier: GPL-3.0-only
# --

package Kernel::System::D724::CatalogPortal;

use v5.24;
use strict;
use warnings;

our $VERSION = '0.2.1';
our @ObjectDependencies = ('Kernel::System::D724::Catalog');

sub new {
    my ($Type) = @_;
    return bless {}, $Type;
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
            ID        => 'customer:' . $Param{CustomerUserID},
            Roles     => ['requester'],
            TenantIDs => [ $Param{CustomerID} ],
        },
    };
}

1;
