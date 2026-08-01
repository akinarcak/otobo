# --
# CareOnCloud ESM enterprise service management platform.
# Copyright (C) 2026 Data Market Bilgi Hizmetleri A.S.
# SPDX-License-Identifier: GPL-3.0-only
# --

package Kernel::Modules::AgentD724Request;

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
    my $RequestObject = $Kernel::OM->Get('Kernel::System::D724::Request');
    my $Context = $Directory->ContextGet( UserID => $Self->{UserID} );
    return $Layout->NoPermission( WithHeader => 'yes' ) if !$Context->{Success};
    my $TenantID = $WebRequest->GetParam( Param => 'TenantID' ) // $Context->{Subject}->{TenantIDs}->[0];
    my %OwnTenant = map { $_ => 1 } @{ $Context->{Subject}->{TenantIDs} };
    return $Layout->NoPermission( WithHeader => 'yes' ) if !$OwnTenant{$TenantID};

    my $Subaction = $Self->{Subaction} // q{};
    if ( $Subaction eq 'ApprovalDecide' || $Subaction eq 'TaskUpdate' || $Subaction eq 'ResponseRecord' ) {
        $Layout->ChallengeTokenCheck();
        my %Common = ( UserID => $Self->{UserID}, TenantID => $TenantID, Comment => $WebRequest->GetParam( Param => 'Comment' ) );
        my $Result = $Subaction eq 'ResponseRecord'
            ? $RequestObject->ResponseRecord(
                %Common, RequestID => $WebRequest->GetParam( Param => 'RequestID' ),
            )
            : $Subaction eq 'ApprovalDecide'
            ? $RequestObject->ApprovalDecide(
                %Common, RequestID => $WebRequest->GetParam( Param => 'RequestID' ),
                ExpectedVersion => $WebRequest->GetParam( Param => 'ExpectedVersion' ),
                Decision => $WebRequest->GetParam( Param => 'Decision' ),
            )
            : $RequestObject->TaskUpdate(
                %Common, TaskID => $WebRequest->GetParam( Param => 'TaskID' ),
                ExpectedVersion => $WebRequest->GetParam( Param => 'ExpectedVersion' ),
                Status => $WebRequest->GetParam( Param => 'Status' ),
            );
        return $Layout->Redirect( OP => "Action=AgentD724Request;TenantID=$TenantID" ) if $Result->{Success};
        $Param{Error} = $Result->{Error};
    }

    for my $Candidate ( @{ $Context->{Subject}->{TenantIDs} } ) {
        $Layout->Block( Name => 'TenantOption', Data => { TenantID => $Candidate, Selected => $Candidate eq $TenantID ? 'selected' : q{} } );
    }
    my $List = $RequestObject->AgentList( UserID => $Self->{UserID}, TenantID => $TenantID );
    return $Layout->NoPermission( WithHeader => 'yes' ) if !$List->{Success};
    for my $Request ( @{ $List->{Data} } ) {
        $Layout->Block( Name => 'Request', Data => $Request );
        $Layout->Block( Name => 'Commitment', Data => $_ ) for @{ $Request->{Commitments} // [] };
        my ($OpenResponse) = grep {
            $_->{ObjectiveType} eq 'response' && $_->{Status} !~ m{\A(?:met|breached|cancelled)\z}smx
        } @{ $Request->{Commitments} // [] };
        if ($OpenResponse) {
            $Layout->Block( Name => 'ResponseAction', Data => { TenantID => $TenantID, RequestID => $Request->{RequestID} } );
        }
        for my $Approval ( @{ $Request->{Approvals} } ) {
            next if $Approval->{Status} ne 'pending';
            $Layout->Block( Name => 'Approval', Data => { %{$Approval}, RequestID => $Request->{RequestID}, TenantID => $TenantID } );
        }
        for my $Task ( @{ $Request->{Tasks} } ) {
            next if $Task->{Status} !~ m{\A(?:pending|in_progress)\z}smx;
            $Layout->Block( Name => 'Task', Data => { %{$Task}, TenantID => $TenantID } );
        }
    }
    my $Output = $Layout->Header( Title => 'D724 Requests' );
    $Output .= $Layout->NavigationBar();
    $Output .= $Layout->Notify( Priority => 'Error', Info => $Param{Error} ) if $Param{Error};
    $Output .= $Layout->Output( TemplateFile => 'AgentD724Request', Data => { TenantID => $TenantID } );
    $Output .= $Layout->Footer();
    return $Output;
}

1;
