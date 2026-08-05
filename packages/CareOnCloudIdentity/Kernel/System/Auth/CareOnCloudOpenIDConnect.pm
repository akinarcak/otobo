# --
# Copyright (C) 2026 Data Market Bilgi Hizmetleri A.S.
# SPDX-License-Identifier: GPL-3.0-only
# --
package Kernel::System::Auth::CareOnCloudOpenIDConnect;

use v5.24;
use strict;
use warnings;
use parent qw(Kernel::System::CareOnCloud::OIDCAuthBackend);

sub _Surface { return 'agent' }
sub _DBClass { return 'Kernel::System::Auth::DB' }

1;
