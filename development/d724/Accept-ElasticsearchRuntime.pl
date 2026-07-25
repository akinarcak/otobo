#!/usr/bin/env perl
# --
# Copyright (C) 2026 Data Market Bilgi Hizmetleri A.S.
# SPDX-License-Identifier: GPL-3.0-only
# --
use v5.24;
use strict;
use warnings;
use HTTP::Request ();
use JSON::PP ();
use Kernel::System::ObjectManager;
use Kernel::System::Ticket::D724AuditCustom ();
use LWP::UserAgent ();

my $UserID = $ARGV[0] // 47;
local $Kernel::OM = Kernel::System::ObjectManager->new();
my $Config = $Kernel::OM->Get('Kernel::Config');
die "Elasticsearch is not active\n" if !$Config->Get('Elasticsearch::Active');
my $Webservice = $Kernel::OM->Get('Kernel::System::GenericInterface::Webservice')->WebserviceGet( Name => 'Elasticsearch' );
die "Elasticsearch webservice is not valid\n" if !$Webservice->{ID} || $Webservice->{ValidID} != 1;
die "Elasticsearch host is not private service DNS\n"
    if ( $Webservice->{Config}->{Requester}->{Transport}->{Config}->{Host} // q{} ) ne 'http://elastic:9200';

my $Token = 'D724LIVE' . time . $$;
my $OwnID = 1_900_000_000 + ( $$ % 40_000 );
my $OtherID = $OwnID + 1;
my $OtherTenant = 'runtime-other-tenant';
my $HTTP = LWP::UserAgent->new( timeout => 30 );
my $JSON = JSON::PP->new->canonical;

sub Request {
    my (%Param) = @_;
    my $Request = HTTP::Request->new( $Param{Type}, $Param{URL} );
    if ( defined $Param{Data} ) {
        $Request->header( 'Content-Type' => 'application/json' );
        $Request->content( $Param{Data} );
    }
    my $Response = $HTTP->request($Request);
    die "$Param{Type} $Param{URL} failed: " . $Response->status_line . "\n"
        if !$Response->is_success;
    return $Response;
}

my $Failure;
my $Result;
eval {
    for my $Fixture (
        [ $OwnID, 'd724-demo' ],
        [ $OtherID, $OtherTenant ],
        )
    {
        my ( $ID, $TenantID ) = @{$Fixture};
        Request(
            Type => 'PUT', URL => "http://elastic:9200/ticket/_doc/$ID",
            Data => $JSON->encode({
                TicketID => $ID, TicketNumber => "RUNTIME-$ID", CustomerID => $TenantID,
                CustomerUserID => 'runtime-fixture', GroupID => 1, QueueID => 2,
                Title => $Token, Created => time,
                ArticlesExternal => [], ArticlesInternal => [],
                AttachmentsExternal => [], AttachmentsInternal => [],
            }),
        );
    }
    Request( Type => 'POST', URL => 'http://elastic:9200/ticket/_refresh' );

    my $Search = $Kernel::OM->Get('Kernel::System::Elasticsearch')->TicketSearch(
        Fulltext => $Token, UserID => $UserID, Result => 'ARRAY', Limit => 10,
    );
    die "tenant-scoped Elasticsearch query failed\n" if ref $Search ne 'HASH' || ref $Search->{Data} ne 'ARRAY';
    die "cross-tenant Elasticsearch hit escaped\n"
        if join( q{|}, @{ $Search->{Data} } ) ne "$OwnID";

    my $Cross = $Kernel::OM->Get('Kernel::System::Elasticsearch')->TicketSearch(
        Fulltext => $Token, UserID => $UserID, CustomerID => $OtherTenant, Result => 'ARRAY', Limit => 10,
    );
    die "explicit cross-tenant filter was not denied\n" if defined $Cross;

    $Result = {
        success => JSON::PP::true, elasticsearch_active => JSON::PP::true,
        webservice_id => 0 + $Webservice->{ID}, user_id => 0 + $UserID,
        tenant_id => 'd724-demo', own_hit => 0 + $OwnID,
        cross_tenant_hit_excluded => JSON::PP::true,
        explicit_cross_tenant_denied => JSON::PP::true,
        fixture_documents => 2,
    };
    1;
} or $Failure = $@ || 'unknown runtime acceptance failure';

for my $ID ( $OwnID, $OtherID ) {
    eval { Request( Type => 'DELETE', URL => "http://elastic:9200/ticket/_doc/$ID" ) };
}
eval { Request( Type => 'POST', URL => 'http://elastic:9200/ticket/_refresh' ) };
die $Failure if $Failure;
say $JSON->encode($Result);
