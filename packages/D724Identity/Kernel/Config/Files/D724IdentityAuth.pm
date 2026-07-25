# --
# Copyright (C) 2026 Data Market Bilgi Hizmetleri A.S.
# SPDX-License-Identifier: GPL-3.0-only
# --
package Kernel::Config::Files::D724IdentityAuth;

use v5.24;
use strict;
use warnings;

sub Load {
    my ( $File, $Self ) = @_;

    my $AgentFallback = $Self->{AuthModule} || 'Kernel::System::Auth::DB';
    if ( $AgentFallback ne 'Kernel::System::Auth::D724OpenIDConnect' ) {
        $Self->{'D724::Identity::FallbackAuthModule::Agent'} = $AgentFallback;
    }
    $Self->{'D724::Identity::FallbackAuthModule::Agent'} ||= 'Kernel::System::Auth::DB';

    my $CustomerFallback = $Self->{'Customer::AuthModule'} || 'Kernel::System::CustomerAuth::DB';
    if ( $CustomerFallback ne 'Kernel::System::CustomerAuth::D724OpenIDConnect' ) {
        $Self->{'D724::Identity::FallbackAuthModule::Customer'} = $CustomerFallback;
    }
    $Self->{'D724::Identity::FallbackAuthModule::Customer'} ||= 'Kernel::System::CustomerAuth::DB';

    $Self->{AuthModule}             = 'Kernel::System::Auth::D724OpenIDConnect';
    $Self->{'Customer::AuthModule'} = 'Kernel::System::CustomerAuth::D724OpenIDConnect';

    return;
}

1;
