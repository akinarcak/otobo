# --
# D724 ESM is an enterprise service management platform based on OTOBO.
# Copyright (C) 2026 Data Market Bilgi Hizmetleri A.S.
# SPDX-License-Identifier: GPL-3.0-only
# --

package Kernel::Modules::AdminD724Commitment;

use v5.24;
use strict;
use warnings;

our $ObjectManagerDisabled = 1;

sub new { my ( $Type, %Param ) = @_; return bless { %Param }, $Type }

sub Run {
    my ( $Self, %Param ) = @_;
    my $Layout = $Kernel::OM->Get('Kernel::Output::HTML::Layout');
    my $WebRequest = $Kernel::OM->Get('Kernel::System::Web::Request');
    my $Directory = $Kernel::OM->Get('Kernel::System::D724::TenantDirectory');
    my $Guard = $Kernel::OM->Get('Kernel::System::D724::TenantGuard');
    my $Commitment = $Kernel::OM->Get('Kernel::System::D724::Commitment');
    my $Context = $Directory->ContextGet( UserID => $Self->{UserID} );
    return $Layout->NoPermission( WithHeader => 'yes' ) if !$Context->{Success};
    my @Tenants = grep {
        $Guard->DecisionGet( Subject => $Context->{Subject}, Resource => { TenantID => $_ }, Action => 'catalog.manage' )->{Allowed}
    } @{ $Context->{Subject}->{TenantIDs} };
    return $Layout->NoPermission( WithHeader => 'yes' ) if !@Tenants;
    my %Allowed = map { $_ => 1 } @Tenants;
    my $TenantID = $WebRequest->GetParam( Param => 'TenantID' ) // $Tenants[0];
    return $Layout->NoPermission( WithHeader => 'yes' ) if !$Allowed{$TenantID};
    my %Call = ( Subject => $Context->{Subject}, UserID => $Self->{UserID}, TenantID => $TenantID );

    if ( ( $Self->{Subaction} // q{} ) eq 'PolicySave' ) {
        $Layout->ChallengeTokenCheck();
        my @PauseStatuses = grep { length } map { my $Value = $_; $Value =~ s{\A\s+|\s+\z}{}gsmx; $Value }
            split m{,}smx, ( $WebRequest->GetParam( Param => 'PauseStatuses' ) // q{} );
        my %Values = (
            Name => $WebRequest->GetParam( Param => 'Name' ), CalendarID => $WebRequest->GetParam( Param => 'CalendarID' ),
            TargetSeconds => $WebRequest->GetParam( Param => 'TargetSeconds' ), WarningPercent => $WebRequest->GetParam( Param => 'WarningPercent' ),
            PauseStatuses => \@PauseStatuses, Status => $WebRequest->GetParam( Param => 'Status' ),
        );
        my $ObjectivesJSON = $WebRequest->GetParam( Param => 'ObjectivesJSON' ) // q{};
        if ( length $ObjectivesJSON ) {
            my $Objectives = eval { $Kernel::OM->Get('Kernel::System::JSON')->Decode( Data => $ObjectivesJSON ) };
            if ( $@ || ref $Objectives ne 'ARRAY' ) { $Param{Error} = 'OBJECTIVES_JSON_INVALID' }
            else { $Values{Objectives} = $Objectives }
        }
        my $PolicyID = $WebRequest->GetParam( Param => 'PolicyID' );
        my $Result = $Param{Error} ? { Success => 0, Error => $Param{Error} } : $PolicyID
            ? $Commitment->PolicyUpdate( %Call, %Values, PolicyID => $PolicyID, ExpectedVersion => $WebRequest->GetParam( Param => 'ExpectedVersion' ) )
            : $Commitment->PolicyCreate( %Call, %Values, Key => $WebRequest->GetParam( Param => 'Key' ) );
        return $Layout->Redirect( OP => "Action=AdminD724Commitment;TenantID=$TenantID" ) if $Result->{Success};
        $Param{Error} = $Result->{Error};
    }

    for my $Candidate (@Tenants) {
        $Layout->Block( Name => 'TenantOption', Data => { TenantID => $Candidate, Selected => $Candidate eq $TenantID ? 'selected' : q{} } );
    }
    my $Policies = $Commitment->PolicyList( Subject => $Context->{Subject}, TenantID => $TenantID );
    return $Layout->NoPermission( WithHeader => 'yes' ) if !$Policies->{Success};
    for my $Policy ( @{ $Policies->{Data} } ) {
        my $ObjectivesJSON = @{ $Policy->{Objectives} }
            ? $Kernel::OM->Get('Kernel::System::JSON')->Encode( Data => $Policy->{Objectives}, SortKeys => 1, Pretty => 1 ) : q{};
        $Layout->Block( Name => 'PolicyRow', Data => { %{$Policy}, PauseStatusesText => join( ', ', @{ $Policy->{PauseStatuses} } ), ObjectivesJSON => $ObjectivesJSON, TenantID => $TenantID } );
    }
    my $Output = $Layout->Header( Title => 'D724 Commitments' );
    $Output .= $Layout->NavigationBar();
    $Output .= $Layout->Notify( Priority => 'Error', Info => $Param{Error} ) if $Param{Error};
    $Output .= $Layout->Output( TemplateFile => 'AdminD724Commitment', Data => { TenantID => $TenantID } );
    $Output .= $Layout->Footer();
    return $Output;
}

1;
