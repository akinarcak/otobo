# --
# Copyright (C) 2026 Data Market Bilgi Hizmetleri A.S.
# SPDX-License-Identifier: GPL-3.0-only
# --
package Kernel::System::Ticket::D724AuditCustom;

use v5.24;
use strict;
use warnings;
use Kernel::System::Ticket::Article::Backend::MIMEBase ();
use Kernel::GenericInterface::Operation::Ticket::Common ();
use Kernel::GenericInterface::Invoker::Elasticsearch::Search ();
use Kernel::System::Elasticsearch ();

our $ObjectManagerDisabled = 1;
our $VERSION = '0.8.5';
our $D724SearchContext;
our $D724TicketAuditMergeSuppress;

my $OriginalTicketCreate      = \&Kernel::System::Ticket::TicketCreate;
my $OriginalTicketDelete      = \&Kernel::System::Ticket::TicketDelete;
my $OriginalTicketMerge       = \&Kernel::System::Ticket::TicketMerge;
my $OriginalTicketSearch      = Kernel::System::Ticket::TicketSearch->can('TicketSearch');
my $OriginalTicketTitleUpdate = \&Kernel::System::Ticket::TicketTitleUpdate;
my $OriginalTicketQueueSet    = \&Kernel::System::Ticket::TicketQueueSet;
my $OriginalTicketTypeSet     = \&Kernel::System::Ticket::TicketTypeSet;
my $OriginalTicketServiceSet  = \&Kernel::System::Ticket::TicketServiceSet;
my $OriginalTicketSLASet      = \&Kernel::System::Ticket::TicketSLASet;
my $OriginalPendingTimeSet    = \&Kernel::System::Ticket::TicketPendingTimeSet;
my $OriginalTicketCustomerSet = \&Kernel::System::Ticket::TicketCustomerSet;
my $OriginalTicketLockSet     = \&Kernel::System::Ticket::TicketLockSet;
my $OriginalTicketStateSet    = \&Kernel::System::Ticket::TicketStateSet;
my $OriginalTicketOwnerSet    = \&Kernel::System::Ticket::TicketOwnerSet;
my $OriginalResponsibleSet    = \&Kernel::System::Ticket::TicketResponsibleSet;
my $OriginalTicketPrioritySet = \&Kernel::System::Ticket::TicketPrioritySet;
my $OriginalArticleCreate     = \&Kernel::System::Ticket::Article::Backend::MIMEBase::ArticleCreate;
my $OriginalGIAccessCheck     = Kernel::GenericInterface::Operation::Ticket::Common->can('CheckAccessPermissions');
my $OriginalESSearch          = Kernel::System::Elasticsearch->can('TicketSearch');
my $OriginalESPrepareRequest  = Kernel::GenericInterface::Invoker::Elasticsearch::Search->can('PrepareRequest');

{
    no warnings 'redefine'; ## no critic

    *Kernel::System::Ticket::TicketCreate = sub {
        my ( $Self, %Param ) = @_;
        return $OriginalTicketCreate->( $Self, %Param ) if $Self->{D724TicketAuditSuppress};
        return $Kernel::OM->Get('Kernel::System::D724::TicketAudit')->TicketCreateRun(
            TicketObject => $Self, Original => $OriginalTicketCreate, Param => \%Param,
        );
    };

    *Kernel::System::Ticket::TicketDelete = sub {
        my ( $Self, %Param ) = @_;
        return $OriginalTicketDelete->( $Self, %Param ) if $Self->{D724TicketAuditSuppress};
        return $Kernel::OM->Get('Kernel::System::D724::TicketAudit')->TicketDeleteRun(
            TicketObject => $Self, Original => $OriginalTicketDelete, Param => \%Param,
        );
    };

    *Kernel::System::Ticket::TicketMerge = sub {
        my ( $Self, %Param ) = @_;
        return $OriginalTicketMerge->( $Self, %Param ) if $Self->{D724TicketAuditSuppress};
        return $Kernel::OM->Get('Kernel::System::D724::TicketAudit')->TicketMergeRun(
            TicketObject => $Self, Original => $OriginalTicketMerge, Param => \%Param,
        );
    };

    *Kernel::System::Ticket::TicketSearch = sub {
        my ( $Self, %Param ) = @_;
        return $OriginalTicketSearch->( $Self, %Param )
            if $Self->{D724TicketPolicySuppress}
            || !$Kernel::OM->Get('Kernel::Config')->Get('D724::TicketPolicy::Enabled');

        my $Policy = $Kernel::OM->Get('Kernel::System::D724::TicketPolicy')->SearchScopeApply(
            Param => \%Param,
        );
        return if !$Policy->{Success};

        return $OriginalTicketSearch->( $Self, %{ $Policy->{Param} } );
    };

    *Kernel::System::Elasticsearch::TicketSearch = sub {
        my ( $Self, %Param ) = @_;
        my $Context = $Kernel::OM->Get('Kernel::System::D724::SearchPolicy')->ContextCreate(%Param);
        return if !$Context->{Success};
        my $Scoped = $Kernel::OM->Get('Kernel::System::D724::TicketPolicy')->SearchScopeApply(
            Param => \%Param,
        );
        return if !$Scoped->{Success};
        local $D724SearchContext = $Context;
        return $OriginalESSearch->( $Self, %{ $Scoped->{Param} } );
    };

    *Kernel::GenericInterface::Invoker::Elasticsearch::Search::PrepareRequest = sub {
        my ( $Self, %Param ) = @_;
        my $Filtered = $Kernel::OM->Get('Kernel::System::D724::SearchPolicy')->RequestFilterApply(
            Data => $Param{Data}, Context => $D724SearchContext,
        );
        return {
            Success => 0, ErrorMessage => 'D724 Elasticsearch search denied: ' . ( $Filtered->{Reason} // 'UNKNOWN' ), Data => {},
        } if !$Filtered->{Success};
        $Param{Data} = $Filtered->{Data};
        return $OriginalESPrepareRequest->( $Self, %Param );
    };

    my $Wrap = sub {
        my ( $Method, $Original, $Action, $Field ) = @_;
        no strict 'refs'; ## no critic
        *{"Kernel::System::Ticket::$Method"} = sub {
            my ( $Self, %Param ) = @_;
            return $Original->( $Self, %Param ) if $Self->{D724TicketAuditSuppress};
            return $Kernel::OM->Get('Kernel::System::D724::TicketAudit')->MutationRun(
                TicketObject => $Self, Original => $Original, Param => \%Param,
                Action => $Action, Field => $Field,
            );
        };
    };
    $Wrap->( 'TicketTitleUpdate',       $OriginalTicketTitleUpdate, 'ticket.title.updated',       'Title' );
    $Wrap->( 'TicketQueueSet',          $OriginalTicketQueueSet,    'ticket.queue.updated',       'Queue' );
    $Wrap->( 'TicketTypeSet',           $OriginalTicketTypeSet,     'ticket.type.updated',        'Type' );
    $Wrap->( 'TicketServiceSet',        $OriginalTicketServiceSet,  'ticket.service.updated',     'Service' );
    $Wrap->( 'TicketSLASet',            $OriginalTicketSLASet,      'ticket.sla.updated',         'SLAID' );
    $Wrap->( 'TicketPendingTimeSet',    $OriginalPendingTimeSet,    'ticket.pending_time.updated', 'UntilTime' );
    $Wrap->( 'TicketCustomerSet',       $OriginalTicketCustomerSet, 'ticket.customer.updated',    'Customer' );
    $Wrap->( 'TicketLockSet',           $OriginalTicketLockSet,     'ticket.lock.updated',        'Lock' );
    $Wrap->( 'TicketStateSet',          $OriginalTicketStateSet,    'ticket.state.updated',       'State' );
    $Wrap->( 'TicketOwnerSet',          $OriginalTicketOwnerSet,    'ticket.owner.updated',       'OwnerID' );
    $Wrap->( 'TicketResponsibleSet',    $OriginalResponsibleSet,    'ticket.responsible.updated', 'ResponsibleID' );
    $Wrap->( 'TicketPrioritySet',       $OriginalTicketPrioritySet, 'ticket.priority.updated',    'Priority' );

    *Kernel::System::Ticket::Article::Backend::MIMEBase::ArticleCreate = sub {
        my ( $Self, %Param ) = @_;
        return $OriginalArticleCreate->( $Self, %Param ) if $Self->{D724TicketAuditSuppress} || $D724TicketAuditMergeSuppress;
        return $Kernel::OM->Get('Kernel::System::D724::TicketAudit')->ArticleCreateRun(
            ArticleBackend => $Self, Original => $OriginalArticleCreate, Param => \%Param,
        );
    };

    *Kernel::GenericInterface::Operation::Ticket::Common::CheckAccessPermissions = sub {
        my ( $Self, %Param ) = @_;
        my $CoreAccess = $OriginalGIAccessCheck->( $Self, %Param );
        return if !$CoreAccess;
        return $CoreAccess if !$Kernel::OM->Get('Kernel::Config')->Get('D724::TicketPolicy::Enabled');

        my %Identity = $Param{UserType} eq 'Customer'
            ? ( CustomerUserID => $Param{UserID} )
            : ( UserID => $Param{UserID} );
        my $Action = $Param{D724Action};
        if ( !defined $Action ) {
            my %OperationAction = (
                'Kernel::GenericInterface::Operation::Ticket::TicketGet'        => 'integration.ticket.get',
                'Kernel::GenericInterface::Operation::Ticket::TicketHistoryGet' => 'integration.ticket.history',
                'Kernel::GenericInterface::Operation::Ticket::TicketUpdate'     => 'integration.ticket.update',
            );
            for my $Depth ( 0 .. 12 ) {
                my $Caller = caller $Depth;
                last if !defined $Caller;
                if ( $OperationAction{$Caller} ) {
                    $Action = $OperationAction{$Caller};
                    last;
                }
            }
        }
        return if !defined $Action;

        my $Policy = $Kernel::OM->Get('Kernel::System::D724::TicketPolicy')->TicketAccessCheck(
            TicketID => $Param{TicketID}, Action => $Action, %Identity,
        );
        return $Policy->{Success} ? 1 : undef;
    };
}

1;
