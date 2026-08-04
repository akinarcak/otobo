# --
# Copyright (C) 2026 Data Market Bilgi Hizmetleri A.S.
# SPDX-License-Identifier: GPL-3.0-only
# --
package Kernel::Config::Files::CareOnCloudIdentityAuth;

use v5.24;
use strict;
use warnings;

sub Load {
    my ( $File, $Self ) = @_;

    my $AgentFallback = $Self->{AuthModule} || 'Kernel::System::Auth::DB';
    if ( $AgentFallback ne 'Kernel::System::Auth::CareOnCloudOpenIDConnect' ) {
        $Self->{'CareOnCloud::Identity::FallbackAuthModule::Agent'} = $AgentFallback;
    }
    $Self->{'CareOnCloud::Identity::FallbackAuthModule::Agent'} ||= 'Kernel::System::Auth::DB';

    my $CustomerFallback = $Self->{'Customer::AuthModule'} || 'Kernel::System::CustomerAuth::DB';
    if ( $CustomerFallback ne 'Kernel::System::CustomerAuth::CareOnCloudOpenIDConnect' ) {
        $Self->{'CareOnCloud::Identity::FallbackAuthModule::Customer'} = $CustomerFallback;
    }
    $Self->{'CareOnCloud::Identity::FallbackAuthModule::Customer'} ||= 'Kernel::System::CustomerAuth::DB';

    $Self->{AuthModule}             = 'Kernel::System::Auth::CareOnCloudOpenIDConnect';
    $Self->{'Customer::AuthModule'} = 'Kernel::System::CustomerAuth::CareOnCloudOpenIDConnect';

    return;
}

1;
