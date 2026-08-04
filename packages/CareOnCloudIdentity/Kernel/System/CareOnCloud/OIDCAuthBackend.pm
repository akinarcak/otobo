# --
# Copyright (C) 2026 Data Market Bilgi Hizmetleri A.S.
# SPDX-License-Identifier: GPL-3.0-only
# --
package Kernel::System::CareOnCloud::OIDCAuthBackend;

use v5.24;
use strict;
use warnings;

use Crypt::PRNG qw(random_bytes);
use MIME::Base64 qw(encode_base64url);

our $VERSION = '0.3.0';
our @ObjectDependencies = qw(
    Kernel::Config
    Kernel::Output::HTML::Layout
    Kernel::System::CareOnCloud::OIDCWeb
    Kernel::System::Log
    Kernel::System::Main
    Kernel::System::Web::Request
);

sub new {
    my ( $Type, %Param ) = @_;
    my $Surface = $Type->_Surface();
    my $FallbackClass = $Kernel::OM->Get('Kernel::Config')->Get(
        $Surface eq 'agent'
            ? 'CareOnCloud::Identity::FallbackAuthModule::Agent'
            : 'CareOnCloud::Identity::FallbackAuthModule::Customer'
    ) || $Type->_DBClass();
    die "Recursive CareOnCloud authentication fallback\n"
        if $FallbackClass =~ m{\ACareOnCloud|::CareOnCloudOpenIDConnect\z}smx;
    $Kernel::OM->Get('Kernel::System::Main')->Require($FallbackClass)
        || die "Cannot load fallback authentication backend $FallbackClass\n";
    return bless {
        Count     => $Param{Count} // q{},
        DBBackend => $FallbackClass->new( Count => $Param{Count} // q{} ),
        AuthError => q{},
    }, $Type;
}

sub GetOption {
    my ( $Self, %Param ) = @_;
    return if ( $Param{What} // q{} ) ne 'PreAuth';
    my $Request = $Kernel::OM->Get('Kernel::System::Web::Request');
    return 1
        if ( $Request->GetParam( Param => 'CareOnCloudSSO' ) // q{} ) eq '1'
        && $Request->GetParam( Param => 'TenantID' )
        && $Request->GetParam( Param => 'ProviderKey' );
    return 0;
}

sub PreAuth {
    my ( $Self, %Param ) = @_;
    my $Request = $Kernel::OM->Get('Kernel::System::Web::Request');
    my $Surface = $Self->_Surface();
    my $BrowserBinding = encode_base64url( random_bytes(32) );
    my $ReturnPath = $Surface eq 'agent'
        ? '/careoncloud/index.pl?Action=AgentDashboard'
        : '/careoncloud/customer.pl?Action=CustomerDashboard';
    my $Start = $Kernel::OM->Get('Kernel::System::CareOnCloud::OIDCWeb')->Start(
        TenantID       => $Request->GetParam( Param => 'TenantID' ),
        ProviderKey    => $Request->GetParam( Param => 'ProviderKey' ),
        Surface        => $Surface,
        BrowserBinding => $BrowserBinding,
        ReturnPath     => $ReturnPath,
    );
    if ( !$Start->{Success} ) {
        $Self->{AuthError} = 'Single sign-on is unavailable. Please use password login or contact the administrator.';
        return;
    }
    $Kernel::OM->Get('Kernel::Output::HTML::Layout')->SetCookie(
        Key      => $Start->{Data}->{CookieName},
        Name     => $Start->{Data}->{CookieName},
        Value    => $Start->{Data}->{CookieValue},
        Expires  => '+' . $Start->{Data}->{CookieTTL} . 's',
        Secure   => 1,
        HTTPOnly => 1,
        SameSite => 'lax',
    );
    return { RedirectURL => $Start->{Data}->{RedirectURL} };
}

sub Auth {
    my ( $Self, %Param ) = @_;
    my $Request = $Kernel::OM->Get('Kernel::System::Web::Request');
    my $State = $Request->GetParam( Param => 'state' ) // q{};
    my $Code  = $Request->GetParam( Param => 'code' ) // q{};
    my $ProviderError = $Request->GetParam( Param => 'error' ) // q{};

    if ( !$State && !$Code && !$ProviderError ) {
        return if !$Param{User};
        return $Self->{DBBackend}->Auth(%Param);
    }

    $Self->{AuthError} = 'Single sign-on failed. Please retry or use password login.';
    return if $State !~ m{\A[A-Za-z0-9_-]{20,128}\z}smx;

    my $CookieName = 'CareOnCloudOIDC-' . $State;
    my $Cookie = $Request->GetCookie( Key => $CookieName ) // q{};
    $Kernel::OM->Get('Kernel::Output::HTML::Layout')->SetCookie(
        Key => $CookieName, Name => $CookieName, Value => q{}, Expires => '-1y',
        Secure => 1, HTTPOnly => 1, SameSite => 'lax',
    );
    return if $ProviderError || !$Code;
    my ( $BrowserBinding, $CodeVerifier )
        = $Cookie =~ m{\A([A-Za-z0-9_-]{43})\.([A-Za-z0-9_-]{43,128})\z}smx;
    return if !$BrowserBinding || !$CodeVerifier;

    my $Result = $Kernel::OM->Get('Kernel::System::CareOnCloud::OIDCWeb')->Callback(
        Surface        => $Self->_Surface(),
        State          => $State,
        Code           => $Code,
        BrowserBinding => $BrowserBinding,
        CodeVerifier   => $CodeVerifier,
    );
    return if !$Result->{Success};
    $Self->{RequestedURL} = $Result->{Data}->{ReturnPath};
    $Self->{RequestedURL} =~ s{\A/careoncloud/(?:index|customer)\.pl\??}{}smx;
    $Self->{AuthError} = q{};
    return $Result->{Data}->{Login};
}

sub PostAuth {
    my ($Self) = @_;
    return if !$Self->{RequestedURL};
    return { RequestedURL => $Self->{RequestedURL} };
}

sub Logout {
    my ( $Self, %Param ) = @_;
    return if !$Self->{DBBackend}->can('Logout');
    return $Self->{DBBackend}->Logout(%Param);
}

1;
