#!/usr/bin/env perl
# --
# Copyright (C) 2026 Data Market Bilgi Hizmetleri A.S.
# SPDX-License-Identifier: GPL-3.0-only
# --
use v5.24;
use strict;
use warnings;
use HTTP::Tiny ();
use JSON::PP ();
use URI::Escape qw(uri_escape_utf8);
use Kernel::System::ObjectManager;

my $BaseURL = $ARGV[0] // 'http://127.0.0.1:5000/careoncloud/api/v1';
die "Acceptance URL must use http(s)\n" if $BaseURL !~ m{\Ahttps?://}smx;
my $TenantID = 'd724-demo';
my $RunID = time() . '-' . $$;
my $ClientID = "metric-accept-$RunID";
my $Admin = {
    ID => 'acceptance:api-metrics', TenantIDs => [$TenantID],
    RoleBindings => { $TenantID => ['tenant_admin'] },
};
local $Kernel::OM = Kernel::System::ObjectManager->new();
my $DB = $Kernel::OM->Get('Kernel::System::DB');
my $Auth = $Kernel::OM->Get('Kernel::System::D724::APIAuth');
my $Created = $Auth->ClientCreate(
    Subject => $Admin, TenantID => $TenantID, Name => 'API metric acceptance',
    Role => 'requester', UserID => 1, TokenTTL => 120, RateLimit => 40, ClientID => $ClientID,
);
die "Client creation failed: $Created->{Error}\n" if !$Created->{Success};

sub MetricCount {
    my (%Param) = @_;
    my $Tenant = $Param{Tenant};
    my $Route = $Param{Route};
    my $Status = $Param{Status};
    $DB->Prepare(
        SQL => "SELECT COALESCE(SUM(request_count),0) FROM d724_api_metric WHERE tenant_id = ? AND route_key = ? AND status_code = ? AND window_start = DATE_FORMAT(current_timestamp, '%Y-%m-%d %H:%i:00')",
        Bind => [ \$Tenant, \$Route, \$Status ],
    );
    my ($Count) = $DB->FetchrowArray();
    return 0 + ( $Count // 0 );
}

my $BeforeTickets = MetricCount( Tenant => $TenantID, Route => 'tickets', Status => 200 );
my $BeforeNotFound = MetricCount( Tenant => $TenantID, Route => 'not_found', Status => 404 );
my $BeforePublic401 = MetricCount( Tenant => '__public__', Route => 'tickets', Status => 401 );
my $HTTP = HTTP::Tiny->new( timeout => 20, verify_SSL => 1 );
my ( $Token, $Failure );
my %Evidence;
eval {
    my $Form = 'grant_type=client_credentials&client_id=' . uri_escape_utf8($ClientID)
        . '&client_secret=' . uri_escape_utf8( $Created->{Data}->{ClientSecret} );
    my $TokenResponse = $HTTP->post(
        "$BaseURL/oauth/token",
        { headers => { 'Content-Type' => 'application/x-www-form-urlencoded' }, content => $Form },
    );
    die "Token HTTP status $TokenResponse->{status}\n" if $TokenResponse->{status} != 200;
    $Token = JSON::PP::decode_json( $TokenResponse->{content} )->{data}->{access_token};
    die "Token response invalid\n" if ( $Token // q{} ) !~ m{\A[A-Za-z0-9]{64}\z}smx;

    for ( 1 .. 3 ) {
        my $Response = $HTTP->get(
            "$BaseURL/tickets?limit=1",
            { headers => { Authorization => "Bearer $Token" } },
        );
        die "Ticket metric request HTTP status $Response->{status}\n" if $Response->{status} != 200;
    }
    my $NotFound = $HTTP->get(
        "$BaseURL/metric-raw-object-123456",
        { headers => { Authorization => "Bearer $Token" } },
    );
    die "Unknown route HTTP status $NotFound->{status}\n" if $NotFound->{status} != 404;
    my $Invalid = $HTTP->get(
        "$BaseURL/tickets?limit=1",
        { headers => { Authorization => 'Bearer ' . ( 'A' x 64 ) } },
    );
    die "Invalid token HTTP status $Invalid->{status}\n" if $Invalid->{status} != 401;

    my $TicketDelta = MetricCount( Tenant => $TenantID, Route => 'tickets', Status => 200 ) - $BeforeTickets;
    my $NotFoundDelta = MetricCount( Tenant => $TenantID, Route => 'not_found', Status => 404 ) - $BeforeNotFound;
    my $Public401Delta = MetricCount( Tenant => '__public__', Route => 'tickets', Status => 401 ) - $BeforePublic401;
    die "Successful route metric count mismatch\n" if $TicketDelta != 3;
    die "Unknown route was not normalized\n" if $NotFoundDelta != 1;
    die "Invalid credential metric did not retain public boundary\n" if $Public401Delta != 1;
    $DB->Prepare( SQL => "SELECT COUNT(*) FROM d724_api_metric WHERE route_key LIKE '%/%' OR route_key REGEXP '[0-9]{4,}'" );
    my ($HighCardinality) = $DB->FetchrowArray();
    die "High-cardinality raw route label persisted\n" if $HighCardinality;
    $DB->Prepare(
        SQL => "SELECT COALESCE(SUM(request_count),0), COALESCE(SUM(duration_sum_ms),0), COALESCE(MAX(duration_max_ms),0) FROM d724_api_metric WHERE tenant_id = ? AND route_key = 'tickets' AND status_code = 200 AND window_start = DATE_FORMAT(current_timestamp, '%Y-%m-%d %H:%i:00')",
        Bind => [ \$TenantID ],
    );
    my ( $Count, $DurationSum, $DurationMax ) = $DB->FetchrowArray();
    die "Latency aggregate is invalid\n" if $Count < 3 || $DurationSum < 0 || $DurationMax < 0;

    my $Status = $Kernel::OM->Get('Kernel::System::Console::Command::Admin::D724::APIStatus')->StatusData();
    die "API metric health status failed\n" if !$Status->{Success} || !$Status->{Counts}->{MetricSeriesUnique};
    $Evidence{ticket_requests_recorded} = $TicketDelta;
    $Evidence{normalized_not_found_recorded} = $NotFoundDelta;
    $Evidence{public_unauthorized_recorded} = $Public401Delta;
    $Evidence{route_series_5m} = 0 + $Status->{Counts}->{RouteSeries5m};
    $Evidence{average_latency_ms_5m} = 0 + $Status->{Counts}->{AverageLatencyMS5m};
    $Evidence{maximum_latency_ms_5m} = 0 + $Status->{Counts}->{MaximumLatencyMS5m};
    $Evidence{healthy} = $Status->{Health}->{Healthy} ? JSON::PP::true : JSON::PP::false;
    1;
} or $Failure = $@ || 'Unknown API metric acceptance failure';

my $Revoked = $Auth->ClientRevoke(
    Subject => $Admin, TenantID => $TenantID, ClientID => $ClientID, UserID => 1,
);
$Failure ||= "Client revocation failed: $Revoked->{Error}" if !$Revoked->{Success};
die $Failure if $Failure;
$Evidence{success} = JSON::PP::true;
$Evidence{tenant_id} = $TenantID;
say JSON::PP->new->canonical->encode(\%Evidence);
