# --
# Copyright (C) 2026 Data Market Bilgi Hizmetleri A.S.
# SPDX-License-Identifier: GPL-3.0-only
# --
use v5.24; use strict; use warnings; use Test2::V0; use Digest::SHA qw(sha256_hex); use Kernel::System::UnitTest::RegisterOM;
use Kernel::Modules::PublicCareOnCloudMetrics;
my $Module=$INC{'Kernel/Modules/PublicCareOnCloudMetrics.pm'};
open my $FH,'<',$Module or die "Cannot read $Module: $!"; local $/; my $Source=<$FH>; close $FH;
like($Source,qr/RequestMethod/,'transport restricts the HTTP method');
like($Source,qr/Authorization/,'transport reads bearer authorization');
like($Source,qr/sha256_hex/,'transport hashes the supplied bearer token');
like($Source,qr/WWW-Authenticate/,'transport emits an authentication challenge');
like($Source,qr/text\/plain; version=0\.0\.4/,'transport uses Prometheus content type');
like($Source,qr/no-store/,'transport disables response caching');
unlike($Source,qr/X-CareOnCloud-Metrics-Token/,'transport does not use a non-standard secret header');
is(length(sha256_hex('test-token')),64,'configured token representation is a SHA-256 digest');
my $Transport=Kernel::Modules::PublicCareOnCloudMetrics->new();
ok($Transport->_Equal(sha256_hex('commercial-test-token'),sha256_hex('commercial-test-token')),'constant-time comparator accepts equal digests');
ok(!$Transport->_Equal(sha256_hex('commercial-test-token'),sha256_hex('different-test-token')),'constant-time comparator rejects unequal digests');
done_testing;
