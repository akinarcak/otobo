#!/usr/bin/env perl
# --
# Copyright (C) 2026 Data Market Bilgi Hizmetleri A.S.
# SPDX-License-Identifier: GPL-3.0-only
# --
use v5.24;
use strict;
use warnings;
use HTTP::Tiny ();

my $URL = shift // 'http://127.0.0.1:5000/otobo/public.pl?Action=PublicD724Metrics';
my $Token = $ENV{D724_METRICS_TOKEN} // q{};
die "D724_METRICS_TOKEN must contain 16-256 non-whitespace characters\n"
    if $Token !~ m{\A\S{16,256}\z}smx;

my $HTTP = HTTP::Tiny->new( Timeout => 20, VerifySSL => 1 );
my $Missing = $HTTP->get($URL);
die "Missing token was not rejected with 401\n" if $Missing->{status} != 401;
my $Wrong = $HTTP->get( $URL, { headers => { Authorization => 'Bearer 0000000000000000' } } );
die "Wrong token was not rejected with 401\n" if $Wrong->{status} != 401;
my $Correct = $HTTP->get( $URL, { headers => { Authorization => "Bearer $Token" } } );
die "Authorized scrape failed with HTTP $Correct->{status}\n" if $Correct->{status} != 200;
die "Unexpected metrics content type\n"
    if ( $Correct->{headers}->{'content-type'} // q{} ) !~ m{\Atext/plain;[ ]version=0\.0\.4}smx;
die "Metrics response can be cached\n"
    if ( $Correct->{headers}->{'cache-control'} // q{} ) ne 'no-store';
die "Metrics secret leaked into response\n" if index( $Correct->{content}, $Token ) >= 0;
die "Dynamic labels found in bounded-cardinality output\n" if $Correct->{content} =~ m{\{[^}]+\}}smx;
my @Series = $Correct->{content} =~ m{^(d724_[a-z0-9_]+)[ ][-+]?[0-9]+(?:\.[0-9]+)?$}gmx;
die "Expected 20 metric series, received " . scalar(@Series) . "\n" if @Series != 20;
my %Series = map { $_ => 1 } @Series;
die "Required health series are missing\n"
    if !$Series{d724_up} || !$Series{d724_tenants_active} || !$Series{d724_observability_query_errors};
say 'D724 observability HTTP acceptance: PASS (401/401/200, 20 fixed series)';
