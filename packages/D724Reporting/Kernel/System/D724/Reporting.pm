# --
# Copyright (C) 2026 Data Market Bilgi Hizmetleri A.S.
# SPDX-License-Identifier: GPL-3.0-only
# --
package Kernel::System::D724::Reporting;

use v5.24;
use strict;
use warnings;

our $VERSION = '0.2.0';
our @ObjectDependencies = (
    'Kernel::Config', 'Kernel::System::DB', 'Kernel::System::D724::TenantDirectory',
    'Kernel::System::D724::TenantCache', 'Kernel::System::D724::TenantGuard', 'Kernel::System::JSON',
);

sub new { return bless {}, $_[0] }

sub Summary {
    my ( $Self, %Param ) = @_;
    my $Valid = $Self->_Validate(%Param);
    return $Valid if !$Valid->{Success};
    my $Auth = $Self->_Authorize( %Param, Action => 'report.read' );
    return $Auth if !$Auth->{Success};
    return $Self->_SummaryCached( %Param, Subject => $Auth->{Subject}, Action => 'report.read' );
}

sub Export {
    my ( $Self, %Param ) = @_;
    return $Self->_Error('FORMAT_INVALID') if ( $Param{Format} // q{} ) !~ m{\A(?:csv|json)\z}smx;
    my $Valid = $Self->_Validate(%Param);
    return $Valid if !$Valid->{Success};
    my $Auth = $Self->_Authorize( %Param, Action => 'report.export' );
    return $Auth if !$Auth->{Success};
    my $Result = $Self->_SummaryCached( %Param, Subject => $Auth->{Subject}, Action => 'report.export' );
    return $Result if !$Result->{Success};

    my $TenantFile = $Param{TenantID};
    $TenantFile =~ s{[^a-zA-Z0-9_-]}{_}gsmx;
    my $Name = "d724-operational-$TenantFile-$Param{From}-$Param{To}.$Param{Format}";
    if ( $Param{Format} eq 'json' ) {
        return {
            %{$Result}, Content => $Kernel::OM->Get('Kernel::System::JSON')->Encode( Data => $Result->{Data}, SortKeys => 1, Pretty => 1 ),
            ContentType => 'application/json', FileName => $Name,
        };
    }
    return { %{$Result}, Content => $Self->_CSV( Data => $Result->{Data} ), ContentType => 'text/csv; charset=utf-8', FileName => $Name };
}

sub _Validate {
    my ( $Self, %Param ) = @_;
    return $Self->_Error('REPORTING_DISABLED') if !$Kernel::OM->Get('Kernel::Config')->Get('D724::Reporting::Enabled');
    return $Self->_Error('TENANT_ID_INVALID') if ( $Param{TenantID} // q{} ) !~ m{\A[a-zA-Z0-9][a-zA-Z0-9._:-]{0,127}\z}smx;
    return $Self->_Error('DATE_INVALID') if ( $Param{From} // q{} ) !~ m{\A[0-9]{4}-[0-9]{2}-[0-9]{2}\z}smx || ( $Param{To} // q{} ) !~ m{\A[0-9]{4}-[0-9]{2}-[0-9]{2}\z}smx;
    my $DB = $Kernel::OM->Get('Kernel::System::DB');
    return $Self->_Error('DATE_INVALID') if !$DB->Prepare(
        SQL => 'SELECT DATEDIFF(?, ?), DATE_FORMAT(?, \'%Y-%m-%d\'), DATE_FORMAT(?, \'%Y-%m-%d\')',
        Bind => [ \$Param{To}, \$Param{From}, \$Param{From}, \$Param{To} ], Limit => 1,
    );
    my ( $Days, $FromNormalized, $ToNormalized ) = $DB->FetchrowArray();
    return $Self->_Error('DATE_INVALID') if !defined $Days || $FromNormalized ne $Param{From} || $ToNormalized ne $Param{To} || $Days < 0;
    my $Maximum = $Kernel::OM->Get('Kernel::Config')->Get('D724::Reporting::MaximumRangeDays') // 366;
    return $Self->_Error('RANGE_CONFIG_INVALID') if $Maximum !~ m{\A[1-9][0-9]{0,3}\z}smx;
    return $Self->_Error('RANGE_TOO_LARGE') if $Days + 1 > $Maximum;
    return { Success => 1 };
}

sub _Authorize {
    my ( $Self, %Param ) = @_;
    my $Subject = $Param{Subject};
    if ( ref $Subject ne 'HASH' && $Param{UserID} ) {
        my $Context = $Kernel::OM->Get('Kernel::System::D724::TenantDirectory')->ContextGet( UserID => $Param{UserID} );
        return $Context if !$Context->{Success};
        $Subject = $Context->{Subject};
    }
    my $Decision = $Kernel::OM->Get('Kernel::System::D724::TenantGuard')->DecisionGet(
        Subject => $Subject, Resource => { TenantID => $Param{TenantID} }, Action => $Param{Action},
    );
    return $Self->_Error( 'FORBIDDEN', $Decision->{Reason} ) if !$Decision->{Allowed};
    return { Success => 1, Subject => $Subject };
}

sub _SummaryQuery {
    my ( $Self, %Param ) = @_;
    my $DB = $Kernel::OM->Get('Kernel::System::DB');
    my @RequestStatus;
    return $Self->_Error('QUERY_FAILED') if !$DB->Prepare(
        SQL => 'SELECT status, COUNT(*) FROM d724_request WHERE tenant_id = ? AND create_time >= ? AND create_time < DATE_ADD(?, INTERVAL 1 DAY) GROUP BY status ORDER BY status',
        Bind => [ \$Param{TenantID}, \$Param{From}, \$Param{To} ],
    );
    while ( my ( $Status, $Count ) = $DB->FetchrowArray() ) { push @RequestStatus, { Status => $Status, Count => 0 + $Count } }

    my @CatalogItems;
    return $Self->_Error('QUERY_FAILED') if !$DB->Prepare(
        SQL => 'SELECT c.key_name, c.name, COUNT(r.id) FROM d724_catalog_item c INNER JOIN d724_request r ON r.tenant_id = c.tenant_id AND r.catalog_item_id = c.id WHERE c.tenant_id = ? AND r.create_time >= ? AND r.create_time < DATE_ADD(?, INTERVAL 1 DAY) GROUP BY c.id, c.key_name, c.name ORDER BY c.key_name',
        Bind => [ \$Param{TenantID}, \$Param{From}, \$Param{To} ],
    );
    while ( my ( $Key, $Name, $Count ) = $DB->FetchrowArray() ) { push @CatalogItems, { Key => $Key, Name => $Name, Count => 0 + $Count } }

    my @Commitments;
    return $Self->_Error('QUERY_FAILED') if !$DB->Prepare(
        SQL => 'SELECT i.objective_type, i.status, COUNT(*) FROM d724_commitment_instance i INNER JOIN d724_request r ON r.tenant_id = i.tenant_id AND r.id = i.request_id WHERE i.tenant_id = ? AND r.create_time >= ? AND r.create_time < DATE_ADD(?, INTERVAL 1 DAY) GROUP BY i.objective_type, i.status ORDER BY i.objective_type, i.status',
        Bind => [ \$Param{TenantID}, \$Param{From}, \$Param{To} ],
    );
    while ( my ( $Type, $Status, $Count ) = $DB->FetchrowArray() ) { push @Commitments, { ObjectiveType => $Type, Status => $Status, Count => 0 + $Count } }

    my $TotalRequests = 0; $TotalRequests += $_->{Count} for @RequestStatus;
    my $TotalCommitments = 0; my $Breached = 0;
    for my $Row (@Commitments) { $TotalCommitments += $Row->{Count}; $Breached += $Row->{Count} if $Row->{Status} eq 'breached' }
    return {
        Success => 1,
        Data => {
            SchemaVersion => 1, TenantID => $Param{TenantID}, From => $Param{From}, To => $Param{To},
            Totals => { Requests => $TotalRequests, Commitments => $TotalCommitments, BreachedCommitments => $Breached },
            RequestStatus => \@RequestStatus, CatalogItems => \@CatalogItems, CommitmentStatus => \@Commitments,
        },
    };
}

sub _SummaryCached {
    my ( $Self, %Param ) = @_;
    my $TTL = $Kernel::OM->Get('Kernel::Config')->Get('D724::Reporting::CacheTTLSeconds') // 60;
    return $Self->_Error('CACHE_TTL_INVALID') if $TTL !~ m{\A[1-9][0-9]{0,4}\z}smx;
    my %CacheParam = (
        Subject => $Param{Subject}, TenantID => $Param{TenantID}, Action => $Param{Action},
        Domain => 'reporting', Key => join( q{|}, 'operational-v1', $Param{From}, $Param{To} ),
    );
    my $Cache = $Kernel::OM->Get('Kernel::System::D724::TenantCache');
    my $Cached = $Cache->Get(%CacheParam);
    return $Cached if !$Cached->{Success};
    return { Success => 1, Data => $Cached->{Value}, Cached => 1 } if $Cached->{Hit};
    my $Result = $Self->_SummaryQuery(%Param);
    return $Result if !$Result->{Success};
    my $Stored = $Cache->Set( %CacheParam, Value => $Result->{Data}, TTL => $TTL );
    return $Stored if !$Stored->{Success};
    return { %{$Result}, Cached => 0 };
}

sub _CSV {
    my ( $Self, %Param ) = @_;
    my @Rows = ( [qw(section key label status count)] );
    push @Rows, map { [ 'request_status', q{}, q{}, $_->{Status}, $_->{Count} ] } @{ $Param{Data}->{RequestStatus} };
    push @Rows, map { [ 'catalog_item', $_->{Key}, $_->{Name}, q{}, $_->{Count} ] } @{ $Param{Data}->{CatalogItems} };
    push @Rows, map { [ 'commitment_status', $_->{ObjectiveType}, q{}, $_->{Status}, $_->{Count} ] } @{ $Param{Data}->{CommitmentStatus} };
    return join q{}, map { join( q{,}, map { $Self->_CSVCell($_) } @{$_} ) . "\r\n" } @Rows;
}

sub _CSVCell {
    my ( $Self, $Value ) = @_;
    $Value = q{} if !defined $Value;
    $Value = "$Value";
    $Value =~ s{[\r\n]+}{ }gsmx;
    $Value = q{'} . $Value if $Value =~ m{\A[=+\-@]}smx;
    $Value =~ s{"}{""}gsmx;
    return qq{"$Value"};
}

sub _Error {
    my ( $Self, $Error, $Reason ) = @_;
    my $Result = { Success => 0, Error => $Error };
    $Result->{Reason} = $Reason if defined $Reason;
    return $Result;
}

1;
