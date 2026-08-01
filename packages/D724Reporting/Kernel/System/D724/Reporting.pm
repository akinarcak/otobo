# --
# Copyright (C) 2026 Data Market Bilgi Hizmetleri A.S.
# SPDX-License-Identifier: GPL-3.0-only
# --
package Kernel::System::D724::Reporting;

use v5.24;
use strict;
use warnings;

our $VERSION = '0.4.1';
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

sub CustomReport {
    my ( $Self, %Param ) = @_;
    my $Valid = $Self->_Validate(%Param);
    return $Valid if !$Valid->{Success};
    my $Auth = $Self->_Authorize( %Param, Action => 'report.read' );
    return $Auth if !$Auth->{Success};

    my %Dimension = (
        status         => { SQL => 'r.status',                         Label => 'Status' },
        service        => { SQL => 's.name',                           Label => 'Service category' },
        extension      => { SQL => 'o.name',                           Label => 'Service extension' },
        request_type   => { SQL => 'c.name',                           Label => 'Request type' },
        month          => { SQL => q{DATE_FORMAT(r.create_time, '%Y-%m')}, Label => 'Month' },
    );
    my %Metric = (
        requests       => { SQL => 'COUNT(DISTINCT r.id)', Label => 'Requests' },
        commitments    => { SQL => 'COUNT(DISTINCT i.id)', Label => 'SLA objectives' },
        breaches       => { SQL => q{COUNT(DISTINCT CASE WHEN i.status = 'breached' THEN i.id END)}, Label => 'Breaches' },
        sla_compliance => { SQL => q{COALESCE(ROUND(100 - (100 * COUNT(DISTINCT CASE WHEN i.status = 'breached' THEN i.id END) / NULLIF(COUNT(DISTINCT i.id), 0)), 1), 100)}, Label => 'SLA compliance' },
    );
    my @Dimensions = ref $Param{Dimensions} eq 'ARRAY' ? @{ $Param{Dimensions} } : ( $Param{Dimension} // 'status' );
    my @Metrics    = ref $Param{Metrics} eq 'ARRAY' ? @{ $Param{Metrics} } : ( $Param{Metric} // 'requests' );
    return $Self->_Error('DIMENSION_INVALID') if !@Dimensions || @Dimensions > 3 || grep { !$Dimension{$_} } @Dimensions;
    return $Self->_Error('METRIC_INVALID') if !@Metrics || @Metrics > 4 || grep { !$Metric{$_} } @Metrics;
    my %Seen;
    @Dimensions = grep { !$Seen{"d:$_"}++ } @Dimensions;
    @Metrics    = grep { !$Seen{"m:$_"}++ } @Metrics;

    my @Select = ( map { $Dimension{$_}->{SQL} } @Dimensions, map { $Metric{$_}->{SQL} } @Metrics );
    my @Where = ( 'r.tenant_id = ?', 'r.create_time >= ?', 'r.create_time < DATE_ADD(?, INTERVAL 1 DAY)' );
    my @BindValue = ( $Param{TenantID}, $Param{From}, $Param{To} );
    if ( defined $Param{Status} && length $Param{Status} ) {
        return $Self->_Error('FILTER_INVALID') if $Param{Status} !~ m{\A[a-z][a-z0-9_-]{0,31}\z}smx;
        push @Where, 'r.status = ?';
        push @BindValue, $Param{Status};
    }
    my @Group = map { $Dimension{$_}->{SQL} } @Dimensions;
    my $SQL = 'SELECT ' . join( ', ', @Select )
        . ' FROM d724_request r'
        . ' INNER JOIN d724_catalog_item c ON c.tenant_id = r.tenant_id AND c.id = r.catalog_item_id'
        . ' INNER JOIN d724_service_offering o ON o.tenant_id = c.tenant_id AND o.id = c.offering_id'
        . ' INNER JOIN d724_service s ON s.tenant_id = o.tenant_id AND s.id = o.service_id'
        . ' LEFT JOIN d724_commitment_instance i ON i.tenant_id = r.tenant_id AND i.request_id = r.id'
        . ' WHERE ' . join( ' AND ', @Where )
        . ' GROUP BY ' . join( ', ', @Group )
        . ' ORDER BY ' . join( ', ', @Group );
    my @Bind = map { \$_ } @BindValue;
    my $DB = $Kernel::OM->Get('Kernel::System::DB');
    return $Self->_Error('QUERY_FAILED') if !$DB->Prepare( SQL => $SQL, Bind => \@Bind );
    my @Rows;
    while ( my @Value = $DB->FetchrowArray() ) {
        push @Rows, { Values => [ map { defined $_ ? $_ : q{} } @Value ] };
    }
    return {
        Success => 1,
        Data => {
            TenantID => $Param{TenantID}, From => $Param{From}, To => $Param{To},
            Dimensions => \@Dimensions, Metrics => \@Metrics,
            Columns => [ map { $Dimension{$_}->{Label} } @Dimensions, map { $Metric{$_}->{Label} } @Metrics ],
            Rows => \@Rows,
        },
    };
}

sub CustomExport {
    my ( $Self, %Param ) = @_;
    return $Self->_Error('FORMAT_INVALID') if ( $Param{Format} // q{} ) !~ m{\A(?:csv|json)\z}smx;
    my $Valid = $Self->_Validate(%Param);
    return $Valid if !$Valid->{Success};
    my $Auth = $Self->_Authorize( %Param, Action => 'report.export' );
    return $Auth if !$Auth->{Success};
    my $Result = $Self->CustomReport( %Param, Subject => $Auth->{Subject} );
    return $Result if !$Result->{Success};
    my $TenantFile = $Param{TenantID};
    $TenantFile =~ s{[^a-zA-Z0-9_-]}{_}gsmx;
    my $Name = "careoncloud-custom-$TenantFile-$Param{From}-$Param{To}.$Param{Format}";
    if ( $Param{Format} eq 'json' ) {
        return {
            %{$Result},
            Content => $Kernel::OM->Get('Kernel::System::JSON')->Encode( Data => $Result->{Data}, SortKeys => 1, Pretty => 1 ),
            ContentType => 'application/json', FileName => $Name,
        };
    }
    my @Rows = ( $Result->{Data}->{Columns}, map { $_->{Values} } @{ $Result->{Data}->{Rows} } );
    return {
        %{$Result}, Content => join( q{}, map { join( q{,}, map { $Self->_CSVCell($_) } @{$_} ) . "\r\n" } @Rows ),
        ContentType => 'text/csv; charset=utf-8', FileName => $Name,
    };
}

sub DefinitionCreate {
    my ( $Self, %Param ) = @_;
    return $Self->_Error('USER_ID_INVALID') if ( $Param{UserID} // q{} ) !~ m{\A[1-9][0-9]*\z}smx;
    return $Self->_Error('KEY_INVALID') if ( $Param{Key} // q{} ) !~ m{\A[a-z][a-z0-9_-]{1,99}\z}smx;
    return $Self->_Error('NAME_INVALID') if !defined $Param{Name} || !length $Param{Name} || length $Param{Name} > 200;
    return $Self->_Error('DESCRIPTION_INVALID') if length( $Param{Description} // q{} ) > 2000;
    return $Self->_Error('VISIBILITY_INVALID') if ( $Param{Visibility} // 'private' ) !~ m{\A(?:private|shared)\z}smx;
    my $Report = $Self->CustomReport(%Param);
    return $Report if !$Report->{Success};
    my $Definition = {
        Dimensions => $Report->{Data}->{Dimensions}, Metrics => $Report->{Data}->{Metrics},
        Status => $Param{Status} // q{},
    };
    my $JSON = $Kernel::OM->Get('Kernel::System::JSON')->Encode( Data => $Definition, SortKeys => 1 );
    my ( $TenantID, $Key, $Name, $Description, $UserID, $Visibility ) = (
        $Param{TenantID}, $Param{Key}, $Param{Name}, $Param{Description} // q{}, $Param{UserID}, $Param{Visibility} // 'private',
    );
    my $DB = $Kernel::OM->Get('Kernel::System::DB');
    return $Self->_Error('CREATE_FAILED') if !$DB->Do(
        SQL => 'INSERT INTO d724_report_definition (tenant_id, key_name, name, description, owner_user_id, visibility, definition_json, version, create_time, create_by, change_time, change_by) VALUES (?, ?, ?, ?, ?, ?, ?, 1, current_timestamp, ?, current_timestamp, ?)',
        Bind => [ \$TenantID, \$Key, \$Name, \$Description, \$UserID, \$Visibility, \$JSON, \$UserID, \$UserID ],
    );
    return $Self->DefinitionGet( %Param, ReportKey => $Key );
}

sub DefinitionList {
    my ( $Self, %Param ) = @_;
    my $Base = $Self->_DefinitionAccessValidate(%Param);
    return $Base if !$Base->{Success};
    my ( $TenantID, $UserID, $Shared ) = ( $Param{TenantID}, $Param{UserID}, 'shared' );
    my $DB = $Kernel::OM->Get('Kernel::System::DB');
    return $Self->_Error('QUERY_FAILED') if !$DB->Prepare(
        SQL => 'SELECT id, key_name, name, description, owner_user_id, visibility, definition_json, version, create_time, change_time FROM d724_report_definition WHERE tenant_id = ? AND (owner_user_id = ? OR visibility = ?) ORDER BY name, id',
        Bind => [ \$TenantID, \$UserID, \$Shared ],
    );
    my @Definitions;
    while ( my @Row = $DB->FetchrowArray() ) {
        push @Definitions, $Self->_DefinitionMap( TenantID => $TenantID, Row => \@Row );
    }
    return { Success => 1, Data => \@Definitions };
}

sub DefinitionGet {
    my ( $Self, %Param ) = @_;
    my $Base = $Self->_DefinitionAccessValidate(%Param);
    return $Base if !$Base->{Success};
    my $Where;
    my $Identifier;
    if ( ( $Param{ReportID} // q{} ) =~ m{\A[1-9][0-9]*\z}smx ) { $Where = 'id = ?'; $Identifier = $Param{ReportID}; }
    elsif ( ( $Param{ReportKey} // q{} ) =~ m{\A[a-z][a-z0-9_-]{1,99}\z}smx ) { $Where = 'key_name = ?'; $Identifier = $Param{ReportKey}; }
    else { return $Self->_Error('REPORT_ID_INVALID'); }
    my ( $TenantID, $UserID, $Shared ) = ( $Param{TenantID}, $Param{UserID}, 'shared' );
    my $DB = $Kernel::OM->Get('Kernel::System::DB');
    return $Self->_Error('QUERY_FAILED') if !$DB->Prepare(
        SQL => "SELECT id, key_name, name, description, owner_user_id, visibility, definition_json, version, create_time, change_time FROM d724_report_definition WHERE tenant_id = ? AND $Where AND (owner_user_id = ? OR visibility = ?)",
        Bind => [ \$TenantID, \$Identifier, \$UserID, \$Shared ], Limit => 1,
    );
    my @Row = $DB->FetchrowArray();
    return $Self->_Error('NOT_FOUND') if !@Row;
    return { Success => 1, Data => $Self->_DefinitionMap( TenantID => $TenantID, Row => \@Row ) };
}

sub DefinitionDelete {
    my ( $Self, %Param ) = @_;
    my $Base = $Self->_DefinitionAccessValidate(%Param);
    return $Base if !$Base->{Success};
    return $Self->_Error('REPORT_ID_INVALID') if ( $Param{ReportID} // q{} ) !~ m{\A[1-9][0-9]*\z}smx;
    my ( $TenantID, $UserID, $ReportID ) = @Param{qw(TenantID UserID ReportID)};
    my $DB = $Kernel::OM->Get('Kernel::System::DB');
    return $Self->_Error('DELETE_FAILED') if !$DB->Do(
        SQL => 'DELETE FROM d724_report_definition WHERE tenant_id = ? AND id = ? AND owner_user_id = ?',
        Bind => [ \$TenantID, \$ReportID, \$UserID ],
    );
    return { Success => 1 };
}

sub DefinitionExecute {
    my ( $Self, %Param ) = @_;
    my $Saved = $Self->DefinitionGet(%Param);
    return $Saved if !$Saved->{Success};
    return $Self->CustomReport(
        %Param,
        Dimensions => $Saved->{Data}->{Definition}->{Dimensions},
        Metrics => $Saved->{Data}->{Definition}->{Metrics},
        Status => $Saved->{Data}->{Definition}->{Status},
    );
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

sub TenantLabelGet {
    my ( $Self, %Param ) = @_;
    return $Self->_Error('REPORTING_DISABLED') if !$Kernel::OM->Get('Kernel::Config')->Get('D724::Reporting::Enabled');
    return $Self->_Error('TENANT_ID_INVALID') if ( $Param{TenantID} // q{} ) !~ m{\A[a-zA-Z0-9][a-zA-Z0-9._:-]{0,127}\z}smx;
    my $Auth = $Self->_Authorize( %Param, Action => 'report.read' );
    return $Auth if !$Auth->{Success};
    my $TenantID = $Param{TenantID}; my $Status = 'active';
    my $DB = $Kernel::OM->Get('Kernel::System::DB');
    return $Self->_Error('QUERY_FAILED') if !$DB->Prepare(
        SQL => 'SELECT name FROM d724_tenant WHERE key_name = ? AND status = ?', Bind => [ \$TenantID, \$Status ], Limit => 1,
    );
    my ($Name) = $DB->FetchrowArray();
    return defined $Name ? { Success => 1, Data => { TenantID => $TenantID, Name => $Name } } : $Self->_Error('NOT_FOUND');
}

sub _DefinitionAccessValidate {
    my ( $Self, %Param ) = @_;
    return $Self->_Error('REPORTING_DISABLED') if !$Kernel::OM->Get('Kernel::Config')->Get('D724::Reporting::Enabled');
    return $Self->_Error('TENANT_ID_INVALID') if ( $Param{TenantID} // q{} ) !~ m{\A[a-zA-Z0-9][a-zA-Z0-9._:-]{0,127}\z}smx;
    return $Self->_Error('USER_ID_INVALID') if ( $Param{UserID} // q{} ) !~ m{\A[1-9][0-9]*\z}smx;
    return $Self->_Authorize( %Param, Action => 'report.read' );
}

sub _DefinitionMap {
    my ( $Self, %Param ) = @_;
    my $Row = $Param{Row};
    my $Definition = eval { $Kernel::OM->Get('Kernel::System::JSON')->Decode( Data => $Row->[6] ) };
    $Definition = {} if $@ || ref $Definition ne 'HASH';
    return {
        ReportID => 0 + $Row->[0], TenantID => $Param{TenantID}, Key => $Row->[1], Name => $Row->[2],
        Description => $Row->[3], OwnerUserID => 0 + $Row->[4], Visibility => $Row->[5], Definition => $Definition,
        Version => 0 + $Row->[7], CreateTime => $Row->[8], ChangeTime => $Row->[9],
    };
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
