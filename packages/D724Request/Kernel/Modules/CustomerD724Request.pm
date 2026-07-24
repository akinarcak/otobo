# --
# D724 ESM is an enterprise service management platform based on OTOBO.
# Copyright (C) 2026 Data Market Bilgi Hizmetleri A.S.
# SPDX-License-Identifier: GPL-3.0-only
# --

package Kernel::Modules::CustomerD724Request;

use v5.24;
use strict;
use warnings;

our $ObjectManagerDisabled = 1;

sub new { my ( $Type, %Param ) = @_; return bless { %Param }, $Type }

sub Run {
    my ( $Self, %Param ) = @_;
    my $Layout = $Kernel::OM->Get('Kernel::Output::HTML::Layout');
    my $WebRequest = $Kernel::OM->Get('Kernel::System::Web::Request');
    my $Request = $Kernel::OM->Get('Kernel::System::D724::Request');
    my %Context = ( CustomerUserID => $Self->{UserID}, CustomerID => $Self->{UserCustomerID} );
    my $Result;
    if ( ( $Self->{Subaction} // q{} ) eq 'Submit' ) {
        $Layout->ChallengeTokenCheck();
        my $ItemID = $WebRequest->GetParam( Param => 'CatalogItemID' );
        my $Item = $Kernel::OM->Get('Kernel::System::D724::CatalogPortal')->ItemGet( %Context, CatalogItemID => $ItemID );
        return $Layout->CustomerNoPermission( WithHeader => 'yes' ) if !$Item->{Success};
        my %Answers;
        for my $Field ( @{ $Item->{Data}->{FormSchema}->{Schema}->{fields} } ) {
            if ( $Field->{type} eq 'multiselect' ) {
                my @Values = $WebRequest->GetArray( Param => $Field->{key} );
                $Answers{ $Field->{key} } = \@Values if @Values;
            }
            elsif ( $Field->{type} eq 'checkbox' ) {
                $Answers{ $Field->{key} } = $WebRequest->GetParam( Param => $Field->{key} ) ? 1 : 0;
            }
            else {
                my $Value = $WebRequest->GetParam( Param => $Field->{key} );
                $Answers{ $Field->{key} } = $Value if defined $Value;
            }
        }
        $Result = $Request->CustomerSubmit(
            %Context, CatalogItemID => $ItemID,
            IdempotencyKey => $WebRequest->GetParam( Param => 'IdempotencyKey' ), Answers => \%Answers,
        );
    }
    else {
        $Result = $Request->CustomerGet( %Context, RequestID => $WebRequest->GetParam( Param => 'RequestID' ) );
    }
    $Param{Error} = $Result->{Error} if !$Result->{Success};
    $Param{Request} = $Result->{Data} if $Result->{Success};
    return join q{},
        $Layout->CustomerHeader( Title => 'Service Request' ),
        $Layout->Output( TemplateFile => 'CustomerD724Request', Data => \%Param ),
        $Layout->CustomerFooter();
}

1;
