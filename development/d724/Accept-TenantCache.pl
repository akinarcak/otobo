#!/usr/bin/env perl
# --
# Copyright (C) 2026 Data Market Bilgi Hizmetleri A.S.
# SPDX-License-Identifier: GPL-3.0-only
# --
use v5.24;
use strict;
use warnings;
use JSON::PP ();
use Kernel::System::ObjectManager;

local $Kernel::OM = Kernel::System::ObjectManager->new();
my $DB = $Kernel::OM->Get('Kernel::System::DB');
my $Cache = $Kernel::OM->Get('Kernel::System::D724::TenantCache');
my $Suffix = join q{-}, time, $$;
my @Tenants = ( "cache-accept-a-$Suffix", "cache-accept-b-$Suffix" );
my $Failure;
my $Result;

eval {
    for my $Tenant (@Tenants) {
        my @Value = ( $Tenant, "Cache acceptance $Tenant", 'active', 1, 1, 1 );
        my @Bind = map { \$_ } @Value;
        die "tenant create failed\n" if !$DB->Do(
            SQL => 'INSERT INTO d724_tenant (key_name, name, status, version, create_time, create_by, change_time, change_by) VALUES (?, ?, ?, ?, current_timestamp, ?, current_timestamp, ?)',
            Bind => \@Bind,
        );
    }
    my $SubjectA = { ID => 'cache-accept-a', TenantIDs => [ $Tenants[0] ], RoleBindings => { $Tenants[0] => ['requester'] } };
    my $SubjectB = { ID => 'cache-accept-b', TenantIDs => [ $Tenants[1] ], RoleBindings => { $Tenants[1] => ['requester'] } };
    my %A = ( Subject => $SubjectA, TenantID => $Tenants[0], Action => 'catalog.read', Domain => 'acceptance', Key => 'shared' );
    my %B = ( Subject => $SubjectB, TenantID => $Tenants[1], Action => 'catalog.read', Domain => 'acceptance', Key => 'shared' );
    die "tenant A set failed\n" if !$Cache->Set( %A, Value => 'A', TTL => 300 )->{Success};
    die "tenant B set failed\n" if !$Cache->Set( %B, Value => 'B', TTL => 300 )->{Success};
    die "namespace isolation failed\n" if $Cache->Get(%A)->{Value} ne 'A' || $Cache->Get(%B)->{Value} ne 'B';
    my $Cross = $Cache->Get( %A, Subject => $SubjectB );
    die "cross-tenant read was not denied\n" if $Cross->{Success} || ( $Cross->{Error} // q{} ) ne 'FORBIDDEN';
    my $NamespaceA = $Cache->NamespaceGet( TenantID => $Tenants[0], Domain => 'acceptance', Key => 'shared' );
    my $NamespaceB = $Cache->NamespaceGet( TenantID => $Tenants[1], Domain => 'acceptance', Key => 'shared' );
    die "physical namespace collision\n" if $NamespaceA->{Type} eq $NamespaceB->{Type};
    die "tenant cleanup failed\n" if !$Cache->TenantCleanUp(%A)->{Success};
    die "tenant cleanup escaped namespace\n" if $Cache->Get(%A)->{Hit} || $Cache->Get(%B)->{Value} ne 'B';
    die "tenant B cleanup failed\n" if !$Cache->TenantCleanUp(%B)->{Success};
    $Result = {
        success => JSON::PP::true,
        namespace_isolated => JSON::PP::true,
        cross_tenant_denied => JSON::PP::true,
        cleanup_isolated => JSON::PP::true,
        namespace_version => 1,
        backend_module => $Kernel::OM->Get('Kernel::Config')->Get('Cache::Module') // q{},
    };
    1;
} or $Failure = $@ || 'unknown acceptance failure';

for my $Tenant (@Tenants) {
    $DB->Do( SQL => 'DELETE FROM d724_tenant WHERE key_name = ?', Bind => [ \$Tenant ] );
}
die $Failure if $Failure;
say JSON::PP->new->canonical->encode($Result);
