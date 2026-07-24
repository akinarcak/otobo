# --
# Copyright (C) 2026 Data Market Bilgi Hizmetleri A.S.
# SPDX-License-Identifier: GPL-3.0-only
# --
package Kernel::Modules::PublicD724API;

use v5.24;
use strict;
use warnings;

our $ObjectManagerDisabled = 1;

sub new {
    my ( $Type, %Param ) = @_;
    return bless \%Param, $Type;
}

sub Run {
    my ($Self) = @_;
    my $Request = $Kernel::OM->Get('Kernel::System::Web::Request');
    my $Route   = $Request->GetParam( Param => 'Route' ) // q{};
    my $Method  = uc( $Request->RequestMethod() // q{} );

    if ( $Route eq 'token' ) {
        return $Self->_Respond( Code => 405, Error => 'METHOD_NOT_ALLOWED' ) if $Method ne 'POST';
        return $Self->_Respond( Code => 400, Error => 'UNSUPPORTED_GRANT_TYPE' )
            if ( $Request->GetParam( Param => 'grant_type' ) // q{} ) ne 'client_credentials';
        my $Result = $Kernel::OM->Get('Kernel::System::D724::APIAuth')->TokenIssue(
            ClientID     => $Request->GetParam( Param => 'client_id' ) // q{},
            ClientSecret => $Request->GetParam( Param => 'client_secret' ) // q{},
        );
        return $Self->_Result( Result => $Result, SuccessCode => 200, Token => 1 );
    }

    return $Self->_Respond( Code => 405, Error => 'METHOD_NOT_ALLOWED' ) if $Method ne 'GET';
    my $Bearer = $Self->_Bearer();
    return $Self->_Respond( Code => 401, Error => 'TOKEN_INVALID' ) if !defined $Bearer;

    my $Validated = $Kernel::OM->Get('Kernel::System::D724::APIAuth')->TokenValidate(
        AccessToken => $Bearer,
    );
    return $Self->_Result( Result => $Validated ) if !$Validated->{Success};
    my $TenantID = $Validated->{Data}->{TenantID};

    if ( $Route eq 'tickets' ) {
        my $Result = $Kernel::OM->Get('Kernel::System::D724::API')->TicketList(
            AccessToken => $Bearer,
            TenantID    => $TenantID,
            Limit       => $Request->GetParam( Param => 'limit' ) // 50,
            AfterID     => $Request->GetParam( Param => 'after_id' ) // 0,
        );
        return $Self->_Result( Result => $Result );
    }
    if ( $Route eq 'ticket' ) {
        my $Result = $Kernel::OM->Get('Kernel::System::D724::API')->TicketGet(
            AccessToken => $Bearer,
            TenantID    => $TenantID,
            TicketID    => $Request->GetParam( Param => 'ticket_id' ) // q{},
        );
        return $Self->_Result( Result => $Result );
    }
    return $Self->_Respond( Code => 404, Error => 'ROUTE_NOT_FOUND' );
}

sub _Bearer {
    my ($Self) = @_;
    my $Header = $Kernel::OM->Get('Kernel::System::Web::Request')->Header('Authorization') // q{};
    return if $Header !~ m{\ABearer[ ]+([a-zA-Z0-9]{64})\z}smx;
    return $1;
}

sub _Result {
    my ( $Self, %Param ) = @_;
    my $Result = $Param{Result};
    if ( !$Result->{Success} ) {
        my %CodeFor = (
            INVALID_CLIENT => 401, TOKEN_INVALID => 401, FORBIDDEN => 403,
            CROSS_TENANT => 403, RATE_LIMITED => 429, NOT_FOUND => 404,
            LIMIT_INVALID => 400, CURSOR_INVALID => 400, TICKET_ID_INVALID => 400,
            API_DISABLED => 503, DATABASE_ERROR => 503, RATE_DATABASE_ERROR => 503,
        );
        return $Self->_Respond(
            Code  => $CodeFor{ $Result->{Error} } // 500,
            Error => $Result->{Error} // 'INTERNAL_ERROR',
        );
    }
    my $Data = $Result->{Data} // {};
    if ( $Param{Token} ) {
        $Data = {
            access_token => $Data->{AccessToken}, token_type => $Data->{TokenType},
            expires_in => 0 + $Data->{ExpiresIn}, tenant_id => $Data->{TenantID}, role => $Data->{Role},
        };
    }
    return $Self->_Respond( Code => $Param{SuccessCode} // 200, Data => $Data, Meta => $Result->{Meta} );
}

sub _Respond {
    my ( $Self, %Param ) = @_;
    my $Response = $Kernel::OM->Get('Kernel::System::Web::Response');
    $Response->Code( $Param{Code} );
    $Response->Header( 'Content-Type' => 'application/json; charset=utf-8' );
    $Response->Header( 'Cache-Control' => 'no-store' );
    $Response->Header( 'X-Content-Type-Options' => 'nosniff' );
    $Response->Header( 'WWW-Authenticate' => 'Bearer' ) if $Param{Code} == 401;
    $Response->Header( 'Retry-After' => '60' ) if $Param{Code} == 429;
    my $Envelope = $Param{Error}
        ? { success => 0, error => { code => $Param{Error} } }
        : { success => 1, data => $Param{Data}, ( $Param{Meta} ? ( meta => $Param{Meta} ) : () ) };
    return $Kernel::OM->Get('Kernel::Output::HTML::Layout')->JSONEncode( Data => $Envelope ) // q{};
}

1;
