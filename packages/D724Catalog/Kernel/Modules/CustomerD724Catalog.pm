# --
# CareOnCloud ESM enterprise service management platform.
# Copyright (C) 2026 Data Market Bilgi Hizmetleri A.S.
# SPDX-License-Identifier: GPL-3.0-only
# --

package Kernel::Modules::CustomerD724Catalog;

use v5.24;
use strict;
use warnings;
use Digest::SHA qw(sha256_hex);

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

    my $Subaction = $Self->{Subaction} // q{};
    my $WebRequest = $Kernel::OM->Get('Kernel::System::Web::Request');

    if ( $Subaction eq 'Item' ) {
        my $Rendered = $Self->_ItemRender(
            LayoutObject => $LayoutObject,
            Portal       => $Portal,
            Context      => \%Context,
            Param        => \%Param,
            CatalogItemID => $WebRequest->GetParam( Param => 'CatalogItemID' ),
            ServiceID     => $WebRequest->GetParam( Param => 'ServiceID' ),
            OfferingID    => $WebRequest->GetParam( Param => 'OfferingID' ),
        );
        return $LayoutObject->CustomerNoPermission( WithHeader => 'yes' ) if !$Rendered;
    }
    elsif ( $Subaction eq 'Select' ) {
        my $Catalog = $Portal->CatalogGet(%Context);
        return $LayoutObject->CustomerNoPermission( WithHeader => 'yes' ) if !$Catalog->{Success};

        my $ServiceID     = $WebRequest->GetParam( Param => 'ServiceID' );
        my $OfferingID    = $WebRequest->GetParam( Param => 'OfferingID' );
        my $CatalogItemID = $WebRequest->GetParam( Param => 'CatalogItemID' );
        my ($SelectedService) = grep { defined $ServiceID && $_->{ServiceID} eq $ServiceID } @{ $Catalog->{Data} };
        my ($SelectedOffering) = $SelectedService
            ? grep { defined $OfferingID && $_->{OfferingID} eq $OfferingID } @{ $SelectedService->{Offerings} }
            : ();

        if ( defined $CatalogItemID && length $CatalogItemID ) {
            my $Rendered = $Self->_ItemRender(
                LayoutObject  => $LayoutObject,
                Portal        => $Portal,
                Context       => \%Context,
                Param         => \%Param,
                CatalogItemID => $CatalogItemID,
                ServiceID     => $ServiceID,
                OfferingID    => $OfferingID,
            );
            return $LayoutObject->CustomerNoPermission( WithHeader => 'yes' ) if !$Rendered;
        }
        else {
            $Param{View}       = 'Select';
            $Param{ServiceID}  = $ServiceID // q{};
            $Param{OfferingID} = $OfferingID // q{};
            for my $Service ( @{ $Catalog->{Data} } ) {
                $LayoutObject->Block(
                    Name => 'ServiceSelectOption',
                    Data => {
                        %{$Service},
                        Selected => ( $SelectedService && $Service->{ServiceID} eq $SelectedService->{ServiceID} ) ? 'selected' : q{},
                    },
                );
            }
            if ($SelectedService) {
                for my $Offering ( @{ $SelectedService->{Offerings} } ) {
                    $LayoutObject->Block(
                        Name => 'OfferingSelectOption',
                        Data => {
                            %{$Offering},
                            Selected => ( $SelectedOffering && $Offering->{OfferingID} eq $SelectedOffering->{OfferingID} ) ? 'selected' : q{},
                        },
                    );
                }
            }
            if ($SelectedOffering) {
                $LayoutObject->Block( Name => 'ItemSelectOption', Data => $_ ) for @{ $SelectedOffering->{Items} };
            }
        }
    }
    else {
        $Param{View} = 'Catalog';
        my $Result = $Portal->CatalogGet(%Context);
        return $LayoutObject->CustomerNoPermission( WithHeader => 'yes' ) if !$Result->{Success};
        for my $Service ( @{ $Result->{Data} } ) {
            $LayoutObject->Block( Name => 'ServiceSelectOption', Data => { %{$Service}, Selected => q{} } );
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

sub _ItemRender {
    my ( $Self, %Param ) = @_;
    my $Result = $Param{Portal}->ItemGet(
        %{ $Param{Context} },
        CatalogItemID => $Param{CatalogItemID},
        ( defined $Param{ServiceID}  && length $Param{ServiceID}  ? ( ServiceID  => $Param{ServiceID} )  : () ),
        ( defined $Param{OfferingID} && length $Param{OfferingID} ? ( OfferingID => $Param{OfferingID} ) : () ),
    );
    return if !$Result->{Success};

    my $Data = $Result->{Data};
    $Param{Param}->{View}            = 'Item';
    $Param{Param}->{CatalogItemID}   = $Data->{CatalogItemID};
    $Param{Param}->{ServiceID}       = $Data->{Service}->{ServiceID};
    $Param{Param}->{ServiceName}     = $Data->{Service}->{Name};
    $Param{Param}->{OfferingID}      = $Data->{Offering}->{OfferingID};
    $Param{Param}->{OfferingName}    = $Data->{Offering}->{Name};
    $Param{Param}->{CatalogItemName} = $Data->{Name};
    $Param{Param}->{IdempotencyKey}  = 'portal-' . sha256_hex(
        join q{|}, $Self->{UserID}, $Data->{Service}->{ServiceID}, $Data->{Offering}->{OfferingID}, $Data->{CatalogItemID}, time, rand(),
    );
    $Param{LayoutObject}->Block( Name => 'ItemDetail', Data => $Data );
    $Param{LayoutObject}->Block( Name => 'FormField', Data => $_ ) for @{ $Data->{FormSchema}->{Schema}->{fields} };
    return 1;
}

1;
