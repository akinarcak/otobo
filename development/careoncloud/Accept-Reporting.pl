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

my $TenantID = $ARGV[0] // 'careoncloud-demo';
my $UserID = $ARGV[1] // 47;
my $From = $ARGV[2] // '2026-01-01';
my $To = $ARGV[3] // '2026-12-31';
local $Kernel::OM = Kernel::System::ObjectManager->new();
my $Reporting = $Kernel::OM->Get('Kernel::System::CareOnCloud::Reporting');

my $Summary = $Reporting->Summary( TenantID => $TenantID, UserID => $UserID, From => $From, To => $To );
die "Summary failed: $Summary->{Error}\n" if !$Summary->{Success};
my $CSV = $Reporting->Export( TenantID => $TenantID, UserID => $UserID, From => $From, To => $To, Format => 'csv' );
die "CSV failed: $CSV->{Error}\n" if !$CSV->{Success};
my $JSON = $Reporting->Export( TenantID => $TenantID, UserID => $UserID, From => $From, To => $To, Format => 'json' );
die "JSON failed: $JSON->{Error}\n" if !$JSON->{Success};
die "Requester or idempotency material escaped\n" if $CSV->{Content} =~ m{requester|idempotency|idem-}ismx || $JSON->{Content} =~ m{requester|idempotency|idem-}ismx;

my $Denied = $Reporting->Export(
    TenantID => 'report-accept-forbidden', UserID => $UserID,
    From => $From, To => $To, Format => 'json',
);
die "Cross-tenant export was not denied\n" if $Denied->{Success} || ( $Denied->{Error} // q{} ) ne 'FORBIDDEN';

say JSON::PP->new->canonical->encode({
    success => JSON::PP::true,
    tenant_id => $TenantID,
    from => $From,
    to => $To,
    requests => 0 + $Summary->{Data}->{Totals}->{Requests},
    commitments => 0 + $Summary->{Data}->{Totals}->{Commitments},
    breached_commitments => 0 + $Summary->{Data}->{Totals}->{BreachedCommitments},
    csv_content_type => $CSV->{ContentType},
    json_content_type => $JSON->{ContentType},
    cross_tenant_denied => JSON::PP::true,
    pii_minimized => JSON::PP::true,
});
