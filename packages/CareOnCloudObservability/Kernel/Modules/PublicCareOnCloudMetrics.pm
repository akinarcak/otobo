# --
# Copyright (C) 2026 Data Market Bilgi Hizmetleri A.S.
# SPDX-License-Identifier: GPL-3.0-only
# --
package Kernel::Modules::PublicCareOnCloudMetrics;

use v5.24;
use strict;
use warnings;
use Digest::SHA qw(sha256_hex);

our $ObjectManagerDisabled = 1;
sub new { my ( $Type, %Param ) = @_; return bless \%Param, $Type }

sub Run {
    my ($Self) = @_;
    my $Request = $Kernel::OM->Get('Kernel::System::Web::Request');
    return $Self->_Error( Code => 405, Message => 'method not allowed' )
        if uc( $Request->RequestMethod() // q{} ) ne 'GET';
    my $Config = $Kernel::OM->Get('Kernel::Config');
    return $Self->_Error( Code => 503, Message => 'metrics unavailable' )
        if !$Config->Get('CareOnCloud::Observability::Enabled');
    my $Expected = lc( $Config->Get('CareOnCloud::Observability::MetricsTokenSHA256') // q{} );
    return $Self->_Error( Code => 503, Message => 'metrics unavailable' )
        if $Expected !~ m{\A[0-9a-f]{64}\z}smx;
    my $Header = $Request->Header('Authorization') // q{};
    return $Self->_Error( Code => 401, Message => 'unauthorized', Authenticate => 1 )
        if $Header !~ m{\ABearer[ ]+([^\s]{16,256})\z}smx || !$Self->_Equal( sha256_hex($1), $Expected );
    my $Service = $Kernel::OM->Get('Kernel::System::CareOnCloud::Observability');
    my $Status = $Service->StatusData();
    return $Self->_Error( Code => 503, Message => 'metrics unavailable' ) if !$Status->{Success};
    my $Response = $Kernel::OM->Get('Kernel::System::Web::Response');
    $Response->Code(200);
    $Response->Header( 'Content-Type' => 'text/plain; version=0.0.4; charset=utf-8' );
    $Response->Header( 'Cache-Control' => 'no-store' );
    $Response->Header( 'X-Content-Type-Options' => 'nosniff' );
    return $Service->PrometheusRender( Status => $Status );
}

sub _Equal {
    my ( $Self, $Left, $Right ) = @_;
    return if length($Left) != length($Right);
    my $Difference = 0;
    $Difference |= ord( substr( $Left, $_, 1 ) ) ^ ord( substr( $Right, $_, 1 ) ) for 0 .. length($Left) - 1;
    return $Difference == 0 ? 1 : 0;
}

sub _Error {
    my ( $Self, %Param ) = @_;
    my $Response = $Kernel::OM->Get('Kernel::System::Web::Response');
    $Response->Code( $Param{Code} );
    $Response->Header( 'Content-Type' => 'text/plain; charset=utf-8' );
    $Response->Header( 'Cache-Control' => 'no-store' );
    $Response->Header( 'X-Content-Type-Options' => 'nosniff' );
    $Response->Header( 'WWW-Authenticate' => 'Bearer realm="careoncloud-metrics"' ) if $Param{Authenticate};
    return "$Param{Message}\n";
}

1;
