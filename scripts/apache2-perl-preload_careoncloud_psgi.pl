#!/usr/bin/env perl

# --
# CareOnCloud ESM is a web-based ticketing system for service organisations.
# --
# Copyright (C) 2019-2026 Rother OSS GmbH, https://otobo.io/
# --
# This program is free software: you can redistribute it and/or modify it under
# the terms of the GNU General Public License as published by the Free Software
# Foundation, either version 3 of the License, or (at your option) any later version.
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
# You should have received a copy of the GNU General Public License
# along with this program. If not, see <https://www.gnu.org/licenses/>.
# --

# This mod_perl startup file should be configured as
#     PerlPostConfigRequire /opt/careoncloud/scripts/apache2-perl-preload_careoncloud_psgi.pl
# when Plack::Handler::Apache2 is used.
# See https://metacpan.org/pod/Plack::Handler::Apache2#STARTUP-FILE.

use strict;
use warnings;
use v5.24;

## nofilter(TidyAll::Plugin::OTOBO::Perl::SyntaxCheck)

# core modules

# CPAN modules
use Apache2::ServerUtil     ();
use Plack::Handler::Apache2 ();

# CareOnCloud ESM modules

BEGIN {
    return unless Apache2::ServerUtil::restart_count() > 1;

    Plack::Handler::Apache2->preload('/opt/careoncloud/bin/psgi-bin/careoncloud.psgi');
}

1;
