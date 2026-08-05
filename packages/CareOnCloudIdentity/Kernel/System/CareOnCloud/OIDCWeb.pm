# --
# Copyright (C) 2026 Data Market Bilgi Hizmetleri A.S.
# SPDX-License-Identifier: GPL-3.0-only
# --
package Kernel::System::CareOnCloud::OIDCWeb;

use v5.24;
use strict;
use warnings;

our $VERSION = '0.3.0';
our @ObjectDependencies = qw(
    Kernel::Config
    Kernel::System::CustomerUser
    Kernel::System::DB
    Kernel::System::CareOnCloud::Identity
    Kernel::System::CareOnCloud::OIDCFlow
    Kernel::System::OpenIDConnect
    Kernel::System::OpenIDConnect::Configuration
    Kernel::System::OpenIDConnect::ProfileRepository
    Kernel::System::User
);

sub new { return bless {}, $_[0] }

sub Start {
    my ( $Self, %Param ) = @_;
    my $Input = $Self->_InputValidate(%Param);
    return $Input if !$Input->{Success};

    my $Context = $Self->_ProviderContextGet(%Param);
    return $Context if !$Context->{Success};

    my $Flow = $Kernel::OM->Get('Kernel::System::CareOnCloud::OIDCFlow')->Begin(
        TenantID      => $Param{TenantID},
        ProviderKey   => $Param{ProviderKey},
        BrowserBinding => $Param{BrowserBinding},
        ReturnPath    => $Param{ReturnPath},
    );
    return $Flow if !$Flow->{Success};

    my $URL = $Kernel::OM->Get('Kernel::System::OpenIDConnect')->BuildRedirectURL(
        AuthRequest => {
            ResponseType        => ['code'],
            AdditionalScope     => [qw(profile email groups)],
            State               => $Flow->{Data}->{State},
            Nonce               => $Flow->{Data}->{Nonce},
            CodeChallenge       => $Flow->{Data}->{CodeChallenge},
            CodeChallengeMethod => 'S256',
        },
        ClientSettings   => $Context->{Data}->{Profile}->{ClientSettings},
        ProviderSettings => $Context->{Data}->{Profile}->{ProviderSettings},
    );
    return $Self->_Error('AUTHORIZATION_URL_FAILED') if !$URL;

    return {
        Success => 1,
        Data    => {
            RedirectURL => $URL,
            State       => $Flow->{Data}->{State},
            CookieName  => 'CareOnCloudOIDC-' . $Flow->{Data}->{State},
            CookieValue => $Param{BrowserBinding} . '.' . $Flow->{Data}->{CodeVerifier},
            CookieTTL   => 300,
        },
    };
}

sub Callback {
    my ( $Self, %Param ) = @_;
    return $Self->_Error('SURFACE_INVALID') if ( $Param{Surface} // q{} ) !~ m{\A(?:agent|customer)\z}smx;
    return $Self->_Error('AUTHORIZATION_CODE_INVALID')
        if ( $Param{Code} // q{} ) !~ m{\A[^\x00-\x20]{1,4096}\z}smx;

    my $Exchange = $Kernel::OM->Get('Kernel::System::CareOnCloud::OIDCFlow')->ExchangeContextGet(
        State          => $Param{State},
        BrowserBinding => $Param{BrowserBinding},
        CodeVerifier   => $Param{CodeVerifier},
    );
    return $Exchange if !$Exchange->{Success};

    my $Context = $Self->_ProviderContextGet(
        TenantID    => $Exchange->{Data}->{TenantID},
        ProviderKey => $Exchange->{Data}->{ProviderKey},
        Surface     => $Param{Surface},
    );
    return $Context if !$Context->{Success};

    my $Profile = $Context->{Data}->{Profile};
    my $IDToken = $Kernel::OM->Get('Kernel::System::OpenIDConnect')->RequestIDToken(
        AuthorizationCode => $Param{Code},
        CodeVerifier      => $Param{CodeVerifier},
        ClientSettings    => $Profile->{ClientSettings},
        ProviderSettings  => $Profile->{ProviderSettings},
    );
    return $Self->_Error('TOKEN_EXCHANGE_FAILED') if !$IDToken;

    my $Verified = $Kernel::OM->Get('Kernel::System::CareOnCloud::OIDCFlow')->CallbackVerify(
        State          => $Param{State},
        BrowserBinding => $Param{BrowserBinding},
        CodeVerifier   => $Param{CodeVerifier},
        IDToken        => $IDToken,
        OpenIDConfig   => {
            ClientSettings   => $Profile->{ClientSettings},
            ProviderSettings => $Profile->{ProviderSettings},
        },
    );
    return $Verified if !$Verified->{Success};

    my %Role = map { $_ => 1 } @{ $Verified->{Data}->{Roles} // [] };
    if ( $Param{Surface} eq 'agent' ) {
        return $Self->_Error('SURFACE_ROLE_DENIED')
            if !$Role{agent} && !$Role{service_owner} && !$Role{auditor} && !$Role{tenant_admin};
        my $UserID = $Kernel::OM->Get('Kernel::System::User')->UserLookup(
            UserLogin => $Verified->{Data}->{Login},
        );
        return $Self->_Error('USER_NOT_PROVISIONED') if !$UserID;
        my $TenantID = $Verified->{Data}->{TenantID};
        my $DB = $Kernel::OM->Get('Kernel::System::DB');
        $DB->Prepare(
            SQL => q{SELECT id FROM careoncloud_tenant_agent_role WHERE tenant_id=? AND user_id=? AND status='active'},
            Bind => [ \$TenantID, \$UserID ],
            Limit => 1,
        );
        my ($MembershipID) = $DB->FetchrowArray();
        return $Self->_Error('TENANT_MEMBERSHIP_REQUIRED') if !$MembershipID;
    }
    else {
        my %Customer = $Kernel::OM->Get('Kernel::System::CustomerUser')->CustomerUserDataGet(
            User => $Verified->{Data}->{Login},
        );
        return $Self->_Error('USER_NOT_PROVISIONED')
            if !$Customer{UserID} || ( $Customer{UserCustomerID} // q{} ) ne $Verified->{Data}->{TenantID};
    }

    return {
        Success => 1,
        Data    => {
            Login      => $Verified->{Data}->{Login},
            TenantID   => $Verified->{Data}->{TenantID},
            ReturnPath => $Verified->{Data}->{ReturnPath},
        },
    };
}

sub _InputValidate {
    my ( $Self, %Param ) = @_;
    return $Self->_Error('SURFACE_INVALID') if ( $Param{Surface} // q{} ) !~ m{\A(?:agent|customer)\z}smx;
    return $Self->_Error('BROWSER_BINDING_INVALID')
        if ( $Param{BrowserBinding} // q{} ) !~ m{\A[A-Za-z0-9_-]{32,128}\z}smx;
    return { Success => 1 };
}

sub _ProviderContextGet {
    my ( $Self, %Param ) = @_;
    my $Provider = $Kernel::OM->Get('Kernel::System::CareOnCloud::Identity')->ProviderRouteGetByKey(
        TenantID => $Param{TenantID}, ProviderKey => $Param{ProviderKey},
    );
    return $Self->_Error('SSO_PROVIDER_UNAVAILABLE') if !$Provider;

    my $ProfileName = join ':', 'careoncloud', $Param{TenantID}, $Param{ProviderKey}, $Param{Surface};
    my $Profile = $Kernel::OM->Get('Kernel::System::OpenIDConnect::ProfileRepository')->GetProfile(
        Name => $ProfileName,
    );
    return $Self->_Error('SSO_PROVIDER_UNAVAILABLE') if !$Profile || ( $Profile->{Valid} // 0 ) != 1;
    return $Self->_Error('PROFILE_AUDIENCE_MISMATCH')
        if ( $Profile->{ClientSettings}->{ClientID} // q{} ) ne $Provider->{Audience};

    my $Redirect = $Kernel::OM->Get('Kernel::Config')->Get('CareOnCloud::Identity::OIDC::RedirectURI') // {};
    return $Self->_Error('REDIRECT_URI_INVALID')
        if ref $Redirect ne 'HASH'
        || ( $Profile->{ClientSettings}->{RedirectURI} // q{} ) ne ( $Redirect->{ $Param{Surface} } // q{} );

    my $ProviderData = $Kernel::OM->Get('Kernel::System::OpenIDConnect::Configuration')->GetProviderData(
        OpenIDConfig => {
            ClientSettings   => $Profile->{ClientSettings},
            ProviderSettings => $Profile->{ProviderSettings},
        },
    );
    return $Self->_Error('SSO_PROVIDER_UNAVAILABLE') if ref $ProviderData ne 'HASH';
    my $Metadata = $Kernel::OM->Get('Kernel::System::CareOnCloud::OIDCFlow')->MetadataValidate(
        Provider => $Provider,
        Metadata => $ProviderData->{OpenIDConfiguration},
    );
    return $Metadata if !$Metadata->{Success};

    return { Success => 1, Data => { Provider => $Provider, Profile => $Profile } };
}

sub _Error { return { Success => 0, Error => $_[1] } }

1;
