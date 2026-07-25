# --
# Copyright (C) 2026 Data Market Bilgi Hizmetleri A.S.
# SPDX-License-Identifier: GPL-3.0-only
# --
package Kernel::System::CustomerAuth::D724OpenIDConnect;

use v5.24;
use strict;
use warnings;
use parent qw(Kernel::System::D724::OIDCAuthBackend);

sub _Surface { return 'customer' }
sub _DBClass { return 'Kernel::System::CustomerAuth::DB' }

1;
