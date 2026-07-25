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
    for my $ID ( sort @Tenants ) {
        my $Label = $Reporting->TenantLabelGet( Subject => $Subject, TenantID => $ID );
        $Layout->Block( Name => 'TenantOption', Data => { TenantID => $ID, Name => $Label->{Success} ? $Label->{Data}->{Name} : $ID, Selected => $ID eq $TenantID ? 'selected' : q{} } );
    }
    my $Summary = $Reporting->Summary( Subject => $Subject, TenantID => $TenantID, From => $From, To => $To );
    if ( !$Summary->{Success} ) {
        my $Output = $Layout->Header( Title => 'CareOnCloud Operations Center' ) . $Layout->NavigationBar();
        $Output .= $Layout->Notify( Priority => 'Error', Info => $Summary->{Error} );
        return $Output . $Layout->Footer();
    }
    my $Data = $Summary->{Data};
    $Layout->Block( Name => 'RequestStatusRow', Data => $_ ) for @{ $Data->{RequestStatus} };
    $Layout->Block( Name => 'CatalogItemRow', Data => $_ ) for @{ $Data->{CatalogItems} };
    $Layout->Block( Name => 'CommitmentRow', Data => $_ ) for @{ $Data->{CommitmentStatus} };
    my $Total = $Data->{Totals}->{Commitments} || 0;
    my $Breached = $Data->{Totals}->{BreachedCommitments} || 0;
    my $Compliance = $Total ? int( ( $Total - $Breached ) * 1000 / $Total + 0.5 ) / 10 : 100;
    my $Output = $Layout->Header( Title => 'CareOnCloud Operations Center' ) . $Layout->NavigationBar();
    $Output .= $Layout->Output( TemplateFile => 'AgentD724Operations', Data => { %{$Data->{Totals}}, TenantID => $TenantID, From => $From, To => $To, Compliance => $Compliance, Cached => $Summary->{Cached} ? 1 : 0 } );
    return $Output . $Layout->Footer();
}
1;
