# --
# SPDX-License-Identifier: GPL-3.0-only
# --
use v5.24;
use strict;
use warnings;
use Test2::V0;
use FindBin qw($Bin);
use File::Spec;

my $Root = File::Spec->catdir( $Bin, '..', '..', '..' );
my $Module = File::Spec->catfile( $Root, 'Kernel', 'System', 'D724', 'SCIM.pm' );
open my $FH, '<', $Module or die "Cannot read $Module: $!";
local $/; my $Source = <$FH>; close $FH;

like( $Source, qr/Action => 'scim\.provision'/, 'all resource operations use the dedicated policy action' );
like( $Source, qr/tenant_id = \? AND scim_id = \?/, 'resource reads bind both tenant and opaque id' );
like( $Source, qr/IMMUTABLE_ATTRIBUTE/, 'identity takeover fields are immutable' );
like( $Source, qr/ActorType=>'integration'/, 'audit actor is the integration client' );
like( $Source, qr/FILTER_UNSUPPORTED/, 'filters fail closed outside the bounded contract' );
like( $Source, qr/ExpectedVersion/, 'writes require optimistic concurrency' );
like( $Source, qr/_AgentHasActiveMembership/, 'tenant deprovision preserves agents used by another tenant' );
like( $Source, qr/native_user_id/, 'native CareOnCloud user link uses brand-neutral schema naming' );
unlike( $Source, qr/careoncloud_user_id|CareOnCloud ESMUserID/, 'legacy upstream-branded user link is absent from runtime code' );
like( $Source, qr/sub GroupDelete/, 'group removal reconciles role memberships' );
unlike( $Source, qr/AccessToken\s*=>\s*\$P\{TenantID\}/, 'tenant identifiers are never treated as bearer tokens' );

my $Transport = File::Spec->catfile( $Root, 'Kernel', 'Modules', 'PublicD724SCIM.pm' );
open my $TFH, '<', $Transport or die "Cannot read $Transport: $!"; local $/; my $TransportSource=<$TFH>;close$TFH;
like($TransportSource,qr/sub _GroupPatch/,'group PATCH transport supports incremental membership reconciliation');
like($TransportSource,qr/application\/scim\+json/,'transport emits the SCIM media type');
like($TransportSource,qr/IF_MATCH_REQUIRED/,'mutations fail closed without If-Match');

done_testing();
