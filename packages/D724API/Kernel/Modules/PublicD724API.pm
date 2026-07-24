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

    if ( $Route eq 'openapi' ) {
        return $Self->_Respond( Code => 405, Error => 'METHOD_NOT_ALLOWED' ) if $Method ne 'GET';
        return $Self->_OpenAPI();
    }

    my $Bearer = $Self->_Bearer();
    return $Self->_Respond( Code => 401, Error => 'TOKEN_INVALID' ) if !defined $Bearer;

    my $Validated = $Kernel::OM->Get('Kernel::System::D724::APIAuth')->TokenValidate(
        AccessToken => $Bearer,
    );
    return $Self->_Result( Result => $Validated ) if !$Validated->{Success};
    my $TenantID = $Validated->{Data}->{TenantID};

    if ( $Route eq 'tickets' ) {
        return $Self->_Respond( Code => 405, Error => 'METHOD_NOT_ALLOWED' ) if $Method ne 'GET';
        my $Result = $Kernel::OM->Get('Kernel::System::D724::API')->TicketList(
            AccessToken => $Bearer,
            TenantID    => $TenantID,
            Limit       => $Request->GetParam( Param => 'limit' ) // 50,
            AfterID     => $Request->GetParam( Param => 'after_id' ) // 0,
        );
        return $Self->_Result( Result => $Result );
    }
    if ( $Route eq 'ticket' ) {
        return $Self->_Respond( Code => 405, Error => 'METHOD_NOT_ALLOWED' ) if $Method ne 'GET';
        my $Result = $Kernel::OM->Get('Kernel::System::D724::API')->TicketGet(
            AccessToken => $Bearer,
            TenantID    => $TenantID,
            TicketID    => $Request->GetParam( Param => 'ticket_id' ) // q{},
        );
        return $Self->_Result( Result => $Result );
    }
    if ( $Route eq 'requests' ) {
        return $Self->_Respond( Code => 405, Error => 'METHOD_NOT_ALLOWED' ) if $Method ne 'POST';
        my $ContentType = $Request->Header('Content-Type') // q{};
        return $Self->_Respond( Code => 415, Error => 'CONTENT_TYPE_UNSUPPORTED' )
            if $ContentType !~ m{\Aapplication/json(?:[ ]*;|\z)}ismx;
        my $Content = $Request->Content() // q{};
        return $Self->_Respond( Code => 413, Error => 'BODY_TOO_LARGE' ) if length $Content > 65_536;
        my $Payload = eval { $Kernel::OM->Get('Kernel::System::JSON')->Decode( Data => $Content ) };
        return $Self->_Respond( Code => 400, Error => 'JSON_INVALID' )
            if $@ || ref $Payload ne 'HASH';
        my $Result = $Kernel::OM->Get('Kernel::System::D724::API')->RequestCreate(
            AccessToken   => $Bearer,
            TenantID      => $TenantID,
            IdempotencyKey => $Request->Header('Idempotency-Key') // q{},
            CatalogItemID => $Payload->{catalog_item_id},
            RequesterLogin => $Payload->{requester_login},
            Answers       => $Payload->{answers},
        );
        return $Self->_Result(
            Result => $Result,
            SuccessCode => $Result->{IdempotentReplay} ? 200 : 201,
            Replay => $Result->{IdempotentReplay} ? 1 : 0,
            Location => $Result->{Success} ? 'requests/' . $Result->{Data}->{id} : undef,
        );
    }
    if ( $Route eq 'request' ) {
        return $Self->_Respond( Code => 405, Error => 'METHOD_NOT_ALLOWED' ) if $Method ne 'GET';
        my $Result = $Kernel::OM->Get('Kernel::System::D724::API')->RequestGet(
            AccessToken    => $Bearer,
            TenantID       => $TenantID,
            RequestID      => $Request->GetParam( Param => 'request_id' ) // q{},
            RequesterLogin => $Request->GetParam( Param => 'requester_login' ) // q{},
        );
        return $Self->_Result( Result => $Result );
    }
    if ( $Route eq 'request_approval' ) {
        return $Self->_Respond( Code => 405, Error => 'METHOD_NOT_ALLOWED' ) if $Method ne 'POST';
        my $Payload = $Self->_JSONPayload();
        return $Payload if ref $Payload ne 'HASH';
        my $Result = $Kernel::OM->Get('Kernel::System::D724::API')->RequestApprovalDecide(
            AccessToken     => $Bearer,
            TenantID        => $TenantID,
            RequestID       => $Request->GetParam( Param => 'request_id' ) // q{},
            Decision        => $Payload->{decision},
            ExpectedVersion => $Payload->{expected_version},
            Comment         => $Payload->{comment},
        );
        return $Self->_Result( Result => $Result, Replay => $Result->{IdempotentReplay} ? 1 : 0 );
    }
    if ( $Route eq 'task' ) {
        return $Self->_Respond( Code => 405, Error => 'METHOD_NOT_ALLOWED' ) if $Method ne 'PATCH';
        my $Payload = $Self->_JSONPayload();
        return $Payload if ref $Payload ne 'HASH';
        my $Result = $Kernel::OM->Get('Kernel::System::D724::API')->RequestTaskUpdate(
            AccessToken     => $Bearer,
            TenantID        => $TenantID,
            TaskID          => $Request->GetParam( Param => 'task_id' ) // q{},
            Status          => $Payload->{status},
            ExpectedVersion => $Payload->{expected_version},
            Comment         => $Payload->{comment},
        );
        return $Self->_Result( Result => $Result, Replay => $Result->{IdempotentReplay} ? 1 : 0 );
    }
    return $Self->_Respond( Code => 404, Error => 'ROUTE_NOT_FOUND' );
}

sub _JSONPayload {
    my ($Self) = @_;
    my $Request = $Kernel::OM->Get('Kernel::System::Web::Request');
    my $ContentType = $Request->Header('Content-Type') // q{};
    return $Self->_Respond( Code => 415, Error => 'CONTENT_TYPE_UNSUPPORTED' )
        if $ContentType !~ m{\Aapplication/json(?:[ ]*;|\z)}ismx;
    my $Content = $Request->Content() // q{};
    return $Self->_Respond( Code => 413, Error => 'BODY_TOO_LARGE' ) if length $Content > 65_536;
    my $Payload = eval { $Kernel::OM->Get('Kernel::System::JSON')->Decode( Data => $Content ) };
    return $Self->_Respond( Code => 400, Error => 'JSON_INVALID' )
        if $@ || ref $Payload ne 'HASH';
    return $Payload;
}

sub _OpenAPI {
    my ($Self) = @_;
    my $Home = $Kernel::OM->Get('Kernel::Config')->Get('Home');
    my $Content = $Kernel::OM->Get('Kernel::System::Main')->FileRead(
        Location => "$Home/var/httpd/htdocs/d724/api/openapi-v1.json",
        Mode => 'utf8', Result => 'SCALAR',
    );
    return $Self->_Respond( Code => 503, Error => 'OPENAPI_UNAVAILABLE' )
        if !$Content || ref $Content ne 'SCALAR';
    my $Response = $Kernel::OM->Get('Kernel::System::Web::Response');
    $Response->Code(200);
    $Response->Header( 'Content-Type' => 'application/vnd.oai.openapi+json;version=3.1' );
    $Response->Header( 'Cache-Control' => 'public, max-age=300' );
    $Response->Header( 'X-Content-Type-Options' => 'nosniff' );
    return ${$Content};
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
            REQUESTER_NOT_FOUND => 404,
            IDEMPOTENCY_CONFLICT => 409, VERSION_CONFLICT => 409,
            TRANSITION_INVALID => 409, NO_PENDING_APPROVAL => 409,
            LIMIT_INVALID => 400, CURSOR_INVALID => 400, TICKET_ID_INVALID => 400,
            REQUEST_ID_INVALID => 400, CATALOG_ITEM_ID_INVALID => 400,
            TASK_ID_INVALID => 400, TASK_STATUS_INVALID => 400,
            DECISION_INVALID => 400, VERSION_REQUIRED => 400, COMMENT_INVALID => 400,
            REQUESTER_LOGIN_INVALID => 400, ANSWERS_INVALID => 400,
            IDEMPOTENCY_KEY_INVALID => 400, NOT_AVAILABLE => 400,
            ANSWER_UNKNOWN => 400, ANSWER_REQUIRED => 400, ANSWER_TYPE_INVALID => 400,
            ANSWER_TOO_LONG => 400, ANSWER_OPTION_INVALID => 400,
            APPROVER_ROLE_REQUIRED => 403, INTEGRATION_SUBJECT_INVALID => 403,
            COMMITMENT_SYNC_FAILED => 503,
            API_DISABLED => 503, DATABASE_ERROR => 503, RATE_DATABASE_ERROR => 503,
            REQUEST_DISABLED => 503, TRANSACTION_FAILED => 503, AUDIT_WRITE_FAILED => 503,
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
    my $Response = $Kernel::OM->Get('Kernel::System::Web::Response');
    $Response->Header( 'Idempotent-Replayed' => $Param{Replay} ? 'true' : 'false' )
        if exists $Param{Replay};
    $Response->Header( 'Location' => $Param{Location} ) if $Param{Location};
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
