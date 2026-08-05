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
use Kernel::System::Ticket::CareOnCloudAuditCustom ();

my $UserID = $ARGV[0] // 47;
local $Kernel::OM = Kernel::System::ObjectManager->new();
my $Policy = $Kernel::OM->Get('Kernel::System::CareOnCloud::SearchPolicy');
my $Context = $Policy->ContextCreate( UserID => $UserID );
die "search context failed: $Context->{Reason}\n" if !$Context->{Success};

my $Invoker = bless {}, 'Kernel::GenericInterface::Invoker::Elasticsearch::Search';
my $Direct = $Invoker->PrepareRequest(
    Data => { IndexName => 'ticket', Must => [ { match_all => {} } ] },
);
die "direct unscoped search was not denied\n" if $Direct->{Success};

my $Unsafe;
my $Prepared;
{
    local $Kernel::System::Ticket::CareOnCloudAuditCustom::CareOnCloudSearchContext = $Context;
    $Unsafe = $Invoker->PrepareRequest(
        Data => { IndexName => 'customer', Must => [ { match_all => {} } ] },
    );
    $Prepared = $Invoker->PrepareRequest(
        Data => { IndexName => 'ticket', Must => [ { match => { Title => 'vpn' } } ], Filter => [], Limit => 10 },
    );
}
die "unsafe global index was not denied\n" if $Unsafe->{Success};
die "scoped ticket query failed\n" if !$Prepared->{Success};
my $Filter = $Prepared->{Data}->{query}->{bool}->{filter}->[-1];
my $FilteredTenants = $Filter->{terms}->{CustomerID};
die "mandatory tenant filter missing\n" if ref $FilteredTenants ne 'ARRAY' || !@{$FilteredTenants};
die "serialized filter differs from trusted context\n"
    if join( q{|}, @{$FilteredTenants} ) ne join( q{|}, @{ $Context->{TenantIDs} } );

say JSON::PP->new->canonical->encode({
    success => JSON::PP::true,
    user_id => 0 + $UserID,
    tenant_ids => $Context->{TenantIDs},
    tenant_field => 'CustomerID',
    direct_unscoped_denied => JSON::PP::true,
    unsafe_index_denied => JSON::PP::true,
    serialized_filter_verified => JSON::PP::true,
    elasticsearch_active => $Kernel::OM->Get('Kernel::Config')->Get('Elasticsearch::Active') ? JSON::PP::true : JSON::PP::false,
});
