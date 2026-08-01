# --
# Copyright (C) 2026 Data Market Bilgi Hizmetleri A.S.
# SPDX-License-Identifier: GPL-3.0-only
# --
package Kernel::Modules::AgentD724Operations;
use v5.24;use strict;use warnings;use POSIX qw(strftime);
our $ObjectManagerDisabled = 1;
sub new { my ( $Type, %Param ) = @_; return bless { %Param }, $Type; }
sub Run {
    my ( $Self, %Param ) = @_;
    my $Layout = $Kernel::OM->Get('Kernel::Output::HTML::Layout');
    my $Web = $Kernel::OM->Get('Kernel::System::Web::Request');
    my $Directory = $Kernel::OM->Get('Kernel::System::D724::TenantDirectory');
    my $Guard = $Kernel::OM->Get('Kernel::System::D724::TenantGuard');
    my $Reporting = $Kernel::OM->Get('Kernel::System::D724::Reporting');
    my $Context = $Directory->ContextGet( UserID => $Self->{UserID} );
    return $Layout->NoPermission( WithHeader => 'yes' ) if !$Context->{Success};
    my $Subject = $Context->{Subject};
    my @Tenants = grep { $Guard->DecisionGet( Subject => $Subject, Resource => { TenantID => $_ }, Action => 'report.read' )->{Allowed} } @{ $Subject->{TenantIDs} };
    return $Layout->NoPermission( WithHeader => 'yes' ) if !@Tenants;
    my %Allowed = map { $_ => 1 } @Tenants;
    my $TenantID = $Web->GetParam( Param => 'TenantID' ) // $Tenants[0];
    return $Layout->NoPermission( WithHeader => 'yes' ) if !$Allowed{$TenantID};
    my $Now = time();
    my $To = $Web->GetParam( Param => 'To' ) // strftime( '%Y-%m-%d', localtime $Now );
    my $From = $Web->GetParam( Param => 'From' ) // strftime( '%Y-%m-%d', localtime( $Now - 29 * 86400 ) );
    return $Layout->NoPermission( WithHeader => 'yes' ) if $From !~ m{\A[0-9]{4}-[0-9]{2}-[0-9]{2}\z}smx || $To !~ m{\A[0-9]{4}-[0-9]{2}-[0-9]{2}\z}smx;
    my @Dimensions = $Web->GetArray( Param => 'Dimensions' );
    my @Metrics    = $Web->GetArray( Param => 'Metrics' );
    @Dimensions = ('status') if !@Dimensions;
    @Metrics    = ('requests') if !@Metrics;
    my $Status = $Web->GetParam( Param => 'Status' ) // q{};
    my $ReportID = $Web->GetParam( Param => 'ReportID' ) // q{};
    if ( ( $Self->{Subaction} // q{} ) eq 'LoadSaved' ) {
        my $Saved = $Reporting->DefinitionGet(
            Subject => $Subject, TenantID => $TenantID, UserID => $Self->{UserID}, ReportID => $ReportID,
        );
        return $Layout->NoPermission( WithHeader => 'yes' ) if !$Saved->{Success};
        @Dimensions = @{ $Saved->{Data}->{Definition}->{Dimensions} // [] };
        @Metrics = @{ $Saved->{Data}->{Definition}->{Metrics} // [] };
        $Status = $Saved->{Data}->{Definition}->{Status} // q{};
    }
    my $SavedNotice = 0;
    if ( ( $Self->{Subaction} // q{} ) eq 'SaveReport' ) {
        $Layout->ChallengeTokenCheck();
        my $Created = $Reporting->DefinitionCreate(
            Subject => $Subject, TenantID => $TenantID, UserID => $Self->{UserID}, From => $From, To => $To,
            Dimensions => \@Dimensions, Metrics => \@Metrics, Status => $Status,
            Key => $Web->GetParam( Param => 'ReportKey' ), Name => $Web->GetParam( Param => 'ReportName' ),
            Description => $Web->GetParam( Param => 'ReportDescription' ),
            Visibility => $Web->GetParam( Param => 'ReportVisibility' ) // 'private',
        );
        if ( !$Created->{Success} ) {
            my $Output = $Layout->Header( Title => 'CareOnCloud Operations Center' ) . $Layout->NavigationBar();
            $Output .= $Layout->Notify( Priority => 'Error', Info => $Created->{Error} );
            return $Output . $Layout->Footer();
        }
        $ReportID = $Created->{Data}->{ReportID};
        $SavedNotice = 1;
    }
    if ( ( $Self->{Subaction} // q{} ) eq 'ExportCustom' ) {
        my $Format = $Web->GetParam( Param => 'Format' ) // q{};
        my $Export = $Reporting->CustomExport(
            Subject => $Subject, TenantID => $TenantID, From => $From, To => $To,
            Dimensions => \@Dimensions, Metrics => \@Metrics, Status => $Status, Format => $Format,
        );
        return $Layout->NoPermission( WithHeader => 'yes' ) if !$Export->{Success};
        return $Layout->Attachment(
            ContentType => $Export->{ContentType}, Content => $Export->{Content}, Type => 'attachment',
            Filename => $Export->{FileName}, NoCache => 1,
        );
    }
    for my $ID ( sort @Tenants ) {
        my $Label = $Reporting->TenantLabelGet( Subject => $Subject, TenantID => $ID );
        $Layout->Block( Name => 'TenantOption', Data => { TenantID => $ID, Name => $Label->{Success} ? $Label->{Data}->{Name} : $ID, Selected => $ID eq $TenantID ? 'selected' : q{} } );
    }
    my $Definitions = $Reporting->DefinitionList( Subject => $Subject, TenantID => $TenantID, UserID => $Self->{UserID} );
    return $Layout->NoPermission( WithHeader => 'yes' ) if !$Definitions->{Success};
    for my $Definition ( @{ $Definitions->{Data} } ) {
        $Layout->Block( Name => 'SavedReportOption', Data => {
            %{$Definition}, Selected => $Definition->{ReportID} eq $ReportID ? 'selected' : q{},
        } );
    }
    my $Summary = $Reporting->Summary( Subject => $Subject, TenantID => $TenantID, From => $From, To => $To );
    if ( !$Summary->{Success} ) {
        my $Output = $Layout->Header( Title => 'CareOnCloud Operations Center' ) . $Layout->NavigationBar();
        $Output .= $Layout->Notify( Priority => 'Error', Info => $Summary->{Error} );
        return $Output . $Layout->Footer();
    }
    my $Data = $Summary->{Data};
    my $Custom = $Reporting->CustomReport(
        Subject => $Subject, TenantID => $TenantID, From => $From, To => $To,
        Dimensions => \@Dimensions, Metrics => \@Metrics, Status => $Status,
    );
    if ( !$Custom->{Success} ) {
        my $Output = $Layout->Header( Title => 'CareOnCloud Operations Center' ) . $Layout->NavigationBar();
        $Output .= $Layout->Notify( Priority => 'Error', Info => $Custom->{Error} );
        return $Output . $Layout->Footer();
    }
    my %SelectedDimension = map { $_ => 1 } @Dimensions;
    my %SelectedMetric = map { $_ => 1 } @Metrics;
    for my $Option (
        [ status => 'Status' ], [ service => 'Service category' ], [ extension => 'Service extension' ],
        [ request_type => 'Request type' ], [ month => 'Month' ],
    ) {
        $Layout->Block( Name => 'DimensionOption', Data => { Key => $Option->[0], Label => $Option->[1], Selected => $SelectedDimension{$Option->[0]} ? 'selected' : q{} } );
    }
    for my $Option ( [ requests => 'Requests' ], [ commitments => 'SLA objectives' ], [ breaches => 'Breaches' ], [ sla_compliance => 'SLA compliance' ] ) {
        $Layout->Block( Name => 'MetricOption', Data => { Key => $Option->[0], Label => $Option->[1], Selected => $SelectedMetric{$Option->[0]} ? 'selected' : q{} } );
    }
    $Layout->Block( Name => 'RequestStatusRow', Data => $_ ) for @{ $Data->{RequestStatus} };
    $Layout->Block( Name => 'CatalogItemRow', Data => $_ ) for @{ $Data->{CatalogItems} };
    $Layout->Block( Name => 'CommitmentRow', Data => $_ ) for @{ $Data->{CommitmentStatus} };
    my $Total = $Data->{Totals}->{Commitments} || 0;
    my $Breached = $Data->{Totals}->{BreachedCommitments} || 0;
    my $Compliance = $Total ? int( ( $Total - $Breached ) * 1000 / $Total + 0.5 ) / 10 : 100;
    my $Output = $Layout->Header( Title => 'CareOnCloud Operations Center' ) . $Layout->NavigationBar();
    $Output .= $Layout->Output( TemplateFile => 'AgentD724Operations', Data => {
        %{$Data->{Totals}}, TenantID => $TenantID, From => $From, To => $To, Status => $Status,
        Compliance => $Compliance, Cached => $Summary->{Cached} ? 1 : 0,
        CustomColumns => $Custom->{Data}->{Columns}, CustomRows => $Custom->{Data}->{Rows}, SavedNotice => $SavedNotice,
    } );
    return $Output . $Layout->Footer();
}
1;
