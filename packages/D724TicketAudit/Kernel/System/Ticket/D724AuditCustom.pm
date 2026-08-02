# --
# Copyright (C) 2026 Data Market Bilgi Hizmetleri A.S.
# SPDX-License-Identifier: GPL-3.0-only
# --
package Kernel::System::Ticket::D724AuditCustom;

use v5.24;
use strict;
use warnings;
use Kernel::System::Ticket::Article::Backend::MIMEBase ();
use Kernel::System::Ticket::Article::Backend::Chat ();
use Kernel::System::Ticket::Article::Backend::Invalid ();
use Kernel::GenericInterface::Operation::Ticket::TicketCreate ();
use Kernel::GenericInterface::Operation::Ticket::TicketUpdate ();
use Kernel::GenericInterface::Operation::Ticket::Common ();
use Kernel::GenericInterface::Invoker::Elasticsearch::Search ();
use Kernel::System::Elasticsearch ();
use Kernel::System::GenericAgent ();
use Kernel::System::Console::Command::Maint::Ticket::PendingCheck ();

our $ObjectManagerDisabled = 1;
our $VERSION = '0.8.19';
our $D724SearchContext;
our $D724TicketAuditMergeSuppress;

my $OriginalTicketCreate      = \&Kernel::System::Ticket::TicketCreate;
my $OriginalTicketDelete      = \&Kernel::System::Ticket::TicketDelete;
my $OriginalTicketMerge       = \&Kernel::System::Ticket::TicketMerge;
my $OriginalTicketSearch      = Kernel::System::Ticket::TicketSearch->can('TicketSearch');
my $OriginalTicketTitleUpdate = \&Kernel::System::Ticket::TicketTitleUpdate;
my $OriginalUnlockTimeoutUpdate = \&Kernel::System::Ticket::TicketUnlockTimeoutUpdate;
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
my $OriginalArchiveFlagSet    = \&Kernel::System::Ticket::TicketArchiveFlagSet;
my $OriginalArticleCreate     = \&Kernel::System::Ticket::Article::Backend::MIMEBase::ArticleCreate;
my $OriginalChatArticleCreate = \&Kernel::System::Ticket::Article::Backend::Chat::ArticleCreate;
my $OriginalChatArticleUpdate = \&Kernel::System::Ticket::Article::Backend::Chat::ArticleUpdate;
my $OriginalChatArticleDelete = \&Kernel::System::Ticket::Article::Backend::Chat::ArticleDelete;
my $OriginalInvalidArticleDelete = \&Kernel::System::Ticket::Article::Backend::Invalid::ArticleDelete;
my $OriginalGIAccessCheck     = Kernel::GenericInterface::Operation::Ticket::Common->can('CheckAccessPermissions');
my $OriginalGITicketCreateRun = Kernel::GenericInterface::Operation::Ticket::TicketCreate->can('Run');
my $OriginalGITicketUpdateRun = Kernel::GenericInterface::Operation::Ticket::TicketUpdate->can('Run');
my $OriginalESSearch          = Kernel::System::Elasticsearch->can('TicketSearch');
my $OriginalESPrepareRequest  = Kernel::GenericInterface::Invoker::Elasticsearch::Search->can('PrepareRequest');
my $OriginalPendingCheckRun   = Kernel::System::Console::Command::Maint::Ticket::PendingCheck->can('Run');
my $OriginalGenericAgentJobRun = Kernel::System::GenericAgent->can('JobRun');

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
        my ( $Method, $Original, $Action, $Field, $AllowNested ) = @_;
        no strict 'refs'; ## no critic
        *{"Kernel::System::Ticket::$Method"} = sub {
            my ( $Self, %Param ) = @_;
            return $Original->( $Self, %Param )
                if $Self->{D724TicketAuditSuppress} || $D724TicketAuditMergeSuppress;
            return $Kernel::OM->Get('Kernel::System::D724::TicketAudit')->MutationRun(
                TicketObject => $Self, Original => $Original, Param => \%Param,
                Action => $Action, Field => $Field, AllowNested => $AllowNested,
            );
        };
    };
    $Wrap->( 'TicketTitleUpdate',       $OriginalTicketTitleUpdate, 'ticket.title.updated',       'Title' );
    $Wrap->( 'TicketUnlockTimeoutUpdate', $OriginalUnlockTimeoutUpdate, 'ticket.unlock_timeout.updated', 'UnlockTimeout' );
    $Wrap->( 'TicketQueueSet',          $OriginalTicketQueueSet,    'ticket.queue.updated',       'Queue' );
    $Wrap->( 'TicketTypeSet',           $OriginalTicketTypeSet,     'ticket.type.updated',        'Type' );
    $Wrap->( 'TicketServiceSet',        $OriginalTicketServiceSet,  'ticket.service.updated',     'Service' );
    $Wrap->( 'TicketSLASet',            $OriginalTicketSLASet,      'ticket.sla.updated',         'SLAID' );
    $Wrap->( 'TicketPendingTimeSet',    $OriginalPendingTimeSet,    'ticket.pending_time.updated', 'UntilTime' );
    $Wrap->( 'TicketCustomerSet',       $OriginalTicketCustomerSet, 'ticket.customer.updated',    'Customer' );
    $Wrap->( 'TicketLockSet',           $OriginalTicketLockSet,     'ticket.lock.updated',        'Lock', 1 );
    $Wrap->( 'TicketStateSet',          $OriginalTicketStateSet,    'ticket.state.updated',       'State' );
    $Wrap->( 'TicketOwnerSet',          $OriginalTicketOwnerSet,    'ticket.owner.updated',       'OwnerID' );
    $Wrap->( 'TicketResponsibleSet',    $OriginalResponsibleSet,    'ticket.responsible.updated', 'ResponsibleID' );
    $Wrap->( 'TicketPrioritySet',       $OriginalTicketPrioritySet, 'ticket.priority.updated',    'Priority' );
    $Wrap->( 'TicketArchiveFlagSet',    $OriginalArchiveFlagSet,    'ticket.archive_flag.updated', 'ArchiveFlag' );

    *Kernel::System::Ticket::Article::Backend::MIMEBase::ArticleCreate = sub {
        my ( $Self, %Param ) = @_;
        return $OriginalArticleCreate->( $Self, %Param ) if $Self->{D724TicketAuditSuppress} || $D724TicketAuditMergeSuppress;
        return $Kernel::OM->Get('Kernel::System::D724::TicketAudit')->ArticleCreateRun(
            ArticleBackend => $Self, Original => $OriginalArticleCreate, Param => \%Param,
        );
    };

    *Kernel::System::Ticket::Article::Backend::Chat::ArticleCreate = sub {
        my ( $Self, %Param ) = @_;
        return $OriginalChatArticleCreate->( $Self, %Param ) if $Self->{D724TicketAuditSuppress};
        return $Kernel::OM->Get('Kernel::System::D724::TicketAudit')->ChatArticleCreateRun(
            ArticleBackend => $Self, Original => $OriginalChatArticleCreate, Param => \%Param,
        );
    };

    *Kernel::System::Ticket::Article::Backend::Chat::ArticleUpdate = sub {
        my ( $Self, %Param ) = @_;
        return $OriginalChatArticleUpdate->( $Self, %Param ) if $Self->{D724TicketAuditSuppress};
        return $Kernel::OM->Get('Kernel::System::D724::TicketAudit')->ChatArticleUpdateRun(
            ArticleBackend => $Self, Original => $OriginalChatArticleUpdate, Param => \%Param,
        );
    };

    *Kernel::System::Ticket::Article::Backend::Chat::ArticleDelete = sub {
        my ( $Self, %Param ) = @_;
        return $OriginalChatArticleDelete->( $Self, %Param ) if $Self->{D724TicketAuditSuppress};
        return $Kernel::OM->Get('Kernel::System::D724::TicketAudit')->ChatArticleDeleteRun(
            ArticleBackend => $Self, Original => $OriginalChatArticleDelete, Param => \%Param,
        );
    };

    *Kernel::System::Ticket::Article::Backend::Invalid::ArticleDelete = sub {
        my ( $Self, %Param ) = @_;
        return $OriginalInvalidArticleDelete->( $Self, %Param ) if $Self->{D724TicketAuditSuppress};
        return $Kernel::OM->Get('Kernel::System::D724::TicketAudit')->InvalidArticleDeleteRun(
            ArticleBackend => $Self, Original => $OriginalInvalidArticleDelete, Param => \%Param,
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

    *Kernel::GenericInterface::Operation::Ticket::TicketUpdate::Run = sub {
        my ( $Self, %Param ) = @_;
        return $OriginalGITicketUpdateRun->( $Self, %Param )
            if !$Kernel::OM->Get('Kernel::Config')->Get('D724::TicketAudit::Enabled');
        return $Kernel::OM->Get('Kernel::System::D724::TicketAudit')->GenericInterfaceTicketUpdateRun(
            Operation => $Self, Original => $OriginalGITicketUpdateRun, Param => \%Param,
        );
    };

    *Kernel::GenericInterface::Operation::Ticket::TicketCreate::Run = sub {
        my ( $Self, %Param ) = @_;
        return $OriginalGITicketCreateRun->( $Self, %Param )
            if !$Kernel::OM->Get('Kernel::Config')->Get('D724::TicketAudit::Enabled');
        return $Kernel::OM->Get('Kernel::System::D724::TicketAudit')->GenericInterfaceTicketCreateRun(
            Operation => $Self, Original => $OriginalGITicketCreateRun, Param => \%Param,
        );
    };

    *Kernel::System::Console::Command::Maint::Ticket::PendingCheck::Run = sub {
        my ( $Self, %Param ) = @_;
        return $OriginalPendingCheckRun->( $Self, %Param )
            if !$Kernel::OM->Get('Kernel::Config')->Get('D724::TicketPolicy::Enabled');

        my $DB = $Kernel::OM->Get('Kernel::System::DB');
        return $Self->ExitCodeError() if !$DB->Prepare(
            SQL => "SELECT key_name FROM d724_tenant WHERE status = 'active' ORDER BY key_name",
        );
        my @TenantIDs;
        while ( my @Row = $DB->FetchrowArray() ) { push @TenantIDs, $Row[0] }
        for my $TenantID (@TenantIDs) {
            my $Result = $Kernel::OM->Get('Kernel::System::D724::TicketPolicy')->AutomationScopeRun(
                TenantID => $TenantID, JobName => 'ticket-pending-check',
                Code => sub {
                    my $TicketObject = $Kernel::OM->Get('Kernel::System::Ticket');
                    my @TicketIDs = $TicketObject->TicketSearch(
                        Result => 'ARRAY', StateType => 'pending auto', UserID => 1,
                    );
                    my %Before;
                    for my $TicketID (@TicketIDs) {
                        my %Ticket = $TicketObject->TicketGet( TicketID => $TicketID, DynamicFields => 0, UserID => 1 );
                        $Before{$TicketID} = $Ticket{State};
                    }
                    local $TicketObject->{D724TicketAuditSuppress} = 1;
                    my $ExitCode = $OriginalPendingCheckRun->( $Self, %Param );
                    for my $TicketID (@TicketIDs) {
                        my %Ticket = $TicketObject->TicketGet( TicketID => $TicketID, DynamicFields => 0, UserID => 1 );
                        my $Reconcile = $Kernel::OM->Get('Kernel::System::D724::TicketAudit')->SchedulerPendingCheckReconcile(
                            TicketID => $TicketID, UserID => 1, BeforeState => $Before{$TicketID}, AfterState => $Ticket{State},
                        );
                        return 1 if !$Reconcile->{Success};
                    }
                    return $ExitCode;
                },
            );
            return $Self->ExitCodeError() if !$Result->{Success} || $Result->{Data}->{Result};
        }
        return $Self->ExitCodeOk();
    };

    *Kernel::System::GenericAgent::JobRun = sub {
        my ( $Self, %Param ) = @_;
        return $OriginalGenericAgentJobRun->( $Self, %Param )
            if !$Kernel::OM->Get('Kernel::Config')->Get('D724::TicketPolicy::Enabled');

        my $DB = $Kernel::OM->Get('Kernel::System::DB');
        return if !$DB->Prepare(
            SQL => "SELECT key_name FROM d724_tenant WHERE status = 'active' ORDER BY key_name",
        );
        my @TenantIDs;
        while ( my @Row = $DB->FetchrowArray() ) { push @TenantIDs, $Row[0] }

        for my $TenantID (@TenantIDs) {
            my $Result = $Kernel::OM->Get('Kernel::System::D724::TicketPolicy')->AutomationScopeRun(
                TenantID => $TenantID, JobName => 'generic-agent',
                Code => sub { return $OriginalGenericAgentJobRun->( $Self, %Param ) },
            );
            return if !$Result->{Success} || !$Result->{Data}->{Result};
        }
        return 1;
    };
}

1;
