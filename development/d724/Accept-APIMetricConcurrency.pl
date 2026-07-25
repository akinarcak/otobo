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

my $TenantID = 'd724-demo';
my $Route    = 'metricconcurrency';

if ( ( $ARGV[0] // q{} ) eq '--worker' ) {
    my ( undef, $At, $Duration ) = @ARGV;
    local $Kernel::OM = Kernel::System::ObjectManager->new();
    my $Result = $Kernel::OM->Get('Kernel::System::D724::APIMetric')->Record(
        TenantID => $TenantID,
        Route => $Route,
        Method => 'GET',
        StatusCode => 200,
        ErrorCode => q{},
        DurationMS => $Duration,
        At => $At,
    );
    exit( $Result->{Success} ? 0 : 1 );
}

my $Workers = $ARGV[0] // 12;

local $Kernel::OM = Kernel::System::ObjectManager->new();
my $At = $Kernel::OM->Create('Kernel::System::DateTime')->ToString();
$At =~ s{:[0-9]{2}\z}{:00}smx;
my $DB = $Kernel::OM->Get('Kernel::System::DB');
my @Dimension = ( $TenantID, $At, $Route, 'GET', 200, q{} );
my @DimensionBind = map { \$_ } @Dimension;
$DB->Do(
    SQL => 'DELETE FROM d724_api_metric WHERE tenant_id = ? AND window_start = ? AND route_key = ? AND method_name = ? AND status_code = ? AND error_code = ?',
    Bind => \@DimensionBind,
) or die "Could not clear concurrency fixture\n";

my @Children;
for my $Worker ( 1 .. $Workers ) {
    my $PID = fork();
    die "fork failed: $!\n" if !defined $PID;
    if ( !$PID ) {
        exec $^X, '-I.', '-IKernel/cpan-lib', $0, '--worker', $At, $Worker;
        exit 127;
    }
    push @Children, $PID;
}

my @Failures;
for my $PID (@Children) {
    waitpid( $PID, 0 );
    push @Failures, $PID if $? != 0;
}
die 'Metric workers failed: ' . join( q{,}, @Failures ) . "\n" if @Failures;

$DB->Prepare(
    SQL => 'SELECT COUNT(*), COALESCE(SUM(request_count),0), COALESCE(SUM(duration_sum_ms),0), COALESCE(MAX(duration_max_ms),0) FROM d724_api_metric WHERE tenant_id = ? AND window_start = ? AND route_key = ? AND method_name = ? AND status_code = ? AND error_code = ?',
    Bind => \@DimensionBind,
);
my ( $Series, $Count, $DurationSum, $DurationMax ) = $DB->FetchrowArray();
my $ExpectedSum = $Workers * ( $Workers + 1 ) / 2;
my $Failure;
$Failure = "Expected one series, got $Series" if $Series != 1;
$Failure //= "Expected $Workers requests, got $Count" if $Count != $Workers;
$Failure //= "Expected duration sum $ExpectedSum, got $DurationSum" if $DurationSum != $ExpectedSum;
$Failure //= "Expected duration max $Workers, got $DurationMax" if $DurationMax != $Workers;
$DB->Do(
    SQL => 'DELETE FROM d724_api_metric WHERE tenant_id = ? AND window_start = ? AND route_key = ? AND method_name = ? AND status_code = ? AND error_code = ?',
    Bind => \@DimensionBind,
) or die "Could not remove concurrency fixture\n";
die "$Failure\n" if $Failure;

say JSON::PP->new->canonical->encode({
    success => JSON::PP::true,
    workers => 0 + $Workers,
    series => 0 + $Series,
    request_count => 0 + $Count,
    duration_sum_ms => 0 + $DurationSum,
    duration_max_ms => 0 + $DurationMax,
});
