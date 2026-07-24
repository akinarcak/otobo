# --
# D724 ESM is an enterprise service management platform based on OTOBO.
# Copyright (C) 2026 Data Market Bilgi Hizmetleri A.S.
# SPDX-License-Identifier: GPL-3.0-only
# --

package Kernel::Modules::CustomerD724Catalog;

use v5.24;
use strict;
use warnings;

our $ObjectManagerDisabled = 1;

sub new {
    my ( $Type, %Param ) = @_;
    return bless { %Param }, $Type;
}

sub Run {
    my ( $Self, %Param ) = @_;
    my $LayoutObject = $Kernel::OM->Get('Kernel::Output::HTML::Layout');
    my $Portal       = $Kernel::OM->Get('Kernel::System::D724::CatalogPortal');
    my %Context = (
        CustomerUserID => $Self->{UserID},
        CustomerID     => $Self->{UserCustomerID},
    );

    if ( ( $Self->{Subaction} // q{} ) eq 'Item' ) {
        my $ItemID = $Kernel::OM->Get('Kernel::System::Web::Request')->GetParam( Param => 'CatalogItemID' );
        my $Result = $Portal->ItemGet( %Context, CatalogItemID => $ItemID );
        return $LayoutObject->CustomerNoPermission( WithHeader => 'yes' ) if !$Result->{Success};
        $LayoutObject->Block( Name => 'ItemDetail', Data => $Result->{Data} );
        for my $Field ( @{ $Result->{Data}->{FormSchema}->{Schema}->{fields} } ) {
            $LayoutObject->Block( Name => 'FormField', Data => $Field );
        }
    }
    else {
        my $Result = $Portal->CatalogGet(%Context);
        return $LayoutObject->CustomerNoPermission( WithHeader => 'yes' ) if !$Result->{Success};
        for my $Service ( @{ $Result->{Data} } ) {
            $LayoutObject->Block( Name => 'Service', Data => $Service );
            for my $Offering ( @{ $Service->{Offerings} } ) {
                $LayoutObject->Block( Name => 'Offering', Data => $Offering );
                for my $Item ( @{ $Offering->{Items} } ) {
                    $LayoutObject->Block( Name => 'CatalogItem', Data => $Item );
                }
            }
        }
    }

    return join q{},
        $LayoutObject->CustomerHeader( Title => 'Service Catalog' ),
        $LayoutObject->Output( TemplateFile => 'CustomerD724Catalog', Data => \%Param ),
        $LayoutObject->CustomerFooter();
}

1;
