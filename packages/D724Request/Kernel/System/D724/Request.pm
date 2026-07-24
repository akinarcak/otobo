# --
# D724 ESM is an enterprise service management platform based on OTOBO.
# Copyright (C) 2026 Data Market Bilgi Hizmetleri A.S.
# SPDX-License-Identifier: GPL-3.0-only
# --

package Kernel::System::D724::Request;

use v5.24;
use strict;
use warnings;
use Digest::SHA qw(sha256_hex);

our $VERSION = '0.4.3';
our @ObjectDependencies = (
    'Kernel::Config',
    'Kernel::System::D724::CatalogPortal',
    'Kernel::System::D724::Audit',
    'Kernel::System::D724::TenantDirectory',
    'Kernel::System::D724::TenantGuard',
    'Kernel::System::DB',
    'Kernel::System::JSON',
    'Kernel::System::Log',
);

sub new { return bless {}, $_[0] }

sub CustomerSubmit {
    my ( $Self, %Param ) = @_;
    return $Self->_TransactionRun( Code => sub { return $Self->_CustomerSubmit(%Param) } );
}

sub _CustomerSubmit {
    my ( $Self, %Param ) = @_;
    return $Self->_Error('REQUEST_DISABLED') if !$Kernel::OM->Get('Kernel::Config')->Get('D724::Request::Enabled');
    return $Self->_Error('IDEMPOTENCY_KEY_INVALID')
        if !defined $Param{IdempotencyKey} || $Param{IdempotencyKey} !~ m{\A[a-zA-Z0-9][a-zA-Z0-9._:-]{15,127}\z}smx;
    my $Portal = $Kernel::OM->Get('Kernel::System::D724::CatalogPortal');
    my $Context = $Portal->ContextGet(
        CustomerUserID => $Param{CustomerUserID}, CustomerID => $Param{CustomerID},
    );
    return $Context if !$Context->{Success};
    my $Item = $Portal->ItemGet(
        CustomerUserID => $Param{CustomerUserID}, CustomerID => $Param{CustomerID},
        CatalogItemID => $Param{CatalogItemID},
    );
    return $Item if !$Item->{Success};
    my $Schema = $Item->{Data}->{FormSchema}->{Schema};
    my $Answers = $Self->_AnswersValidate( Schema => $Schema, Answers => $Param{Answers} );
    return $Answers if !$Answers->{Success};
    my $Workflow = $Self->_WorkflowNormalize( Schema => $Schema, Answers => $Answers->{Data} );
    my $JSON = $Kernel::OM->Get('Kernel::System::JSON');
    my $AnswersJSON  = $JSON->Encode( Data => $Answers->{Data}, SortKeys => 1 );
    my $WorkflowJSON = $JSON->Encode( Data => $Workflow, SortKeys => 1 );
    my $PayloadHash  = sha256_hex( join q{|}, $Param{CatalogItemID}, $AnswersJSON, $WorkflowJSON );
    my $TenantID     = $Context->{TenantID};
    my $RequesterID  = $Context->{Subject}->{ID};

    my $Existing = $Self->_RequestByIdempotency(
        TenantID => $TenantID, RequesterID => $RequesterID, IdempotencyKey => $Param{IdempotencyKey},
    );
    if ($Existing) {
        return $Self->_Error('IDEMPOTENCY_CONFLICT') if $Existing->{PayloadHash} ne $PayloadHash;
        my $Data = $Self->_RequestAggregate( TenantID => $TenantID, RequestID => $Existing->{RequestID} );
        return $Self->_Error('INITIALIZATION_FAILED') if !$Data || $Data->{Status} eq 'submission_failed';
        return $Self->_Error('REQUEST_INITIALIZING') if $Data->{Status} eq 'initializing';
        my $Audited = $Self->_AuditRequestCreated(
            TenantID => $TenantID, ActorID => $RequesterID, Request => $Data,
        );
        return $Self->_Error('AUDIT_WRITE_FAILED') if !$Audited->{Success};
        return { Success => 1, Data => $Data, IdempotentReplay => 1 };
    }

    my $TemporaryNumber = 'TMP-' . substr( sha256_hex( join q{|}, $RequesterID, $Param{IdempotencyKey} ), 0, 28 );
    my $Actor = $RequesterID;
    my @Values = (
        $TemporaryNumber, $TenantID, $Param{CatalogItemID}, $RequesterID, $Param{IdempotencyKey},
        $PayloadHash, $AnswersJSON, $WorkflowJSON, 'initializing', 1, $Actor, $Actor,
    );
    my @Bind = map { \$_ } @Values;
    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');
    my $Inserted = $DBObject->Do(
        SQL => 'INSERT INTO d724_request '
            . '(request_number, tenant_id, catalog_item_id, requester_id, idempotency_key, payload_hash, answers_json, workflow_json, status, version, create_time, create_by, change_time, change_by) '
            . 'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, current_timestamp, ?, current_timestamp, ?)',
        Bind => \@Bind,
    );
    if (!$Inserted) {
        my $Raced = $Self->_RequestByIdempotency(
            TenantID => $TenantID, RequesterID => $RequesterID, IdempotencyKey => $Param{IdempotencyKey},
        );
        return $Self->_Error('DATABASE_ERROR') if !$Raced;
        return $Self->_Error('IDEMPOTENCY_CONFLICT') if $Raced->{PayloadHash} ne $PayloadHash;
        my $Data = $Self->_RequestAggregate( TenantID => $TenantID, RequestID => $Raced->{RequestID} );
        my $Audited = $Self->_AuditRequestCreated( TenantID => $TenantID, ActorID => $RequesterID, Request => $Data );
        return $Self->_Error('AUDIT_WRITE_FAILED') if !$Audited->{Success};
        return { Success => 1, Data => $Data, IdempotentReplay => 1 };
    }
    my $Created = $Self->_RequestByIdempotency(
        TenantID => $TenantID, RequesterID => $RequesterID, IdempotencyKey => $Param{IdempotencyKey},
    );
    return $Self->_Error('DATABASE_ERROR') if !$Created;
    my $RequestID = $Created->{RequestID};
    my $RequestNumber = sprintf 'REQ-%010d', $RequestID;
    my $ApprovalRequired = $Workflow->{approval}->{required} ? 1 : 0;
    if ($ApprovalRequired) {
        my ( $Role, $Empty, $Pending ) = ( $Workflow->{approval}->{approver_role}, q{}, 'pending' );
        my @ApprovalValues = ( $TenantID, $RequestID, 1, $Role, $Pending, $Empty );
        my @ApprovalBind = map { \$_ } @ApprovalValues;
        return $Self->_InitializationFail( TenantID => $TenantID, RequestID => $RequestID, Actor => $Actor )
            if !$DBObject->Do(
                SQL => 'INSERT INTO d724_request_approval (tenant_id, request_id, sequence_no, approver_role, status, decision_comment, version, create_time) '
                    . 'VALUES (?, ?, ?, ?, ?, ?, 1, current_timestamp)', Bind => \@ApprovalBind,
            );
    }
    my $TaskStatus = $ApprovalRequired ? 'blocked' : 'pending';
    for my $Task ( @{ $Workflow->{fulfillment} } ) {
        my @TaskValues = ( $TenantID, $RequestID, $Task->{key}, $Task->{name}, $Task->{type}, $TaskStatus, q{}, $Actor );
        my @TaskBind = map { \$_ } @TaskValues;
        return $Self->_InitializationFail( TenantID => $TenantID, RequestID => $RequestID, Actor => $Actor )
            if !$DBObject->Do(
                SQL => 'INSERT INTO d724_request_task (tenant_id, request_id, key_name, name, task_type, status, version, result_comment, create_time, change_time, change_by) '
                    . 'VALUES (?, ?, ?, ?, ?, ?, 1, ?, current_timestamp, current_timestamp, ?)', Bind => \@TaskBind,
            );
    }
    my $FinalStatus = $ApprovalRequired ? 'awaiting_approval' : 'in_fulfillment';
    my @FinalizeValues = ( $RequestNumber, $FinalStatus, $Actor, $TenantID, $RequestID );
    my @FinalizeBind = map { \$_ } @FinalizeValues;
    return $Self->_InitializationFail( TenantID => $TenantID, RequestID => $RequestID, Actor => $Actor )
        if !$DBObject->Do(
            SQL => 'UPDATE d724_request SET request_number = ?, status = ?, change_time = current_timestamp, change_by = ? '
                . 'WHERE tenant_id = ? AND id = ?', Bind => \@FinalizeBind,
        );
    if ( $Workflow->{commitment} ) {
        my $Commitment = $Self->_CommitmentObject();
        return $Self->_InitializationFail( TenantID => $TenantID, RequestID => $RequestID, Actor => $Actor ) if !$Commitment;
        my $Started = $Commitment->StartAll(
            TenantID => $TenantID, RequestID => $RequestID, PolicyKey => $Workflow->{commitment}->{policy_key},
            Actor => $Actor, RequestStatus => $FinalStatus, Signal => 'request_created',
        );
        return $Self->_InitializationFail( TenantID => $TenantID, RequestID => $RequestID, Actor => $Actor ) if !$Started->{Success};
    }
    my $Audited = $Self->_AuditRequestCreated(
        TenantID => $TenantID, ActorID => $Actor,
        Request => $Self->_RequestAggregate( TenantID => $TenantID, RequestID => $RequestID ),
    );
    return $Self->_Error('AUDIT_WRITE_FAILED') if !$Audited->{Success};
    return { Success => 1, Data => $Self->_RequestAggregate( TenantID => $TenantID, RequestID => $RequestID ), IdempotentReplay => 0 };
}

sub CustomerGet {
    my ( $Self, %Param ) = @_;
    return $Self->_Error('REQUEST_DISABLED') if !$Kernel::OM->Get('Kernel::Config')->Get('D724::Request::Enabled');
    return $Self->_Error('REQUEST_ID_INVALID') if !$Self->_PositiveInteger( $Param{RequestID} );
    my $Context = $Kernel::OM->Get('Kernel::System::D724::CatalogPortal')->ContextGet(
        CustomerUserID => $Param{CustomerUserID}, CustomerID => $Param{CustomerID},
    );
    return $Context if !$Context->{Success};
    my $Data = $Self->_RequestAggregate( TenantID => $Context->{TenantID}, RequestID => $Param{RequestID} );
    return $Self->_Error('NOT_FOUND') if !$Data || $Data->{RequesterID} ne $Context->{Subject}->{ID};
    my $Commitment = $Self->_CommitmentObject();
    if ($Commitment) {
        my $Result = $Commitment->CustomerGetByRequest(
            CustomerUserID => $Param{CustomerUserID}, CustomerID => $Param{CustomerID}, RequestID => $Param{RequestID},
        );
        $Data->{Commitment} = $Result->{Data} if $Result->{Success};
        $Data->{Commitments} = $Result->{Objectives} if $Result->{Success};
    }
    return { Success => 1, Data => $Data };
}

sub AgentList {
    my ( $Self, %Param ) = @_;
    return $Self->_Error('REQUEST_DISABLED') if !$Kernel::OM->Get('Kernel::Config')->Get('D724::Request::Enabled');
    my $Context = $Self->_AgentAuthorize( %Param, Action => 'case.read' );
    return $Context if !$Context->{Success};
    my $TenantID = $Param{TenantID};
    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');
    $DBObject->Prepare(
        SQL => "SELECT id FROM d724_request WHERE tenant_id = ? AND status <> 'initializing' AND status <> 'submission_failed' ORDER BY id DESC",
        Bind => [ \$TenantID ], Limit => 200,
    );
    my @Data;
    while ( my ($ID) = $DBObject->FetchrowArray() ) {
        my $Data = $Self->_RequestAggregate( TenantID => $TenantID, RequestID => $ID );
        my $Commitment = $Self->_CommitmentObject();
        if ($Commitment) {
            my $Result = $Commitment->AgentListByRequest( UserID => $Param{UserID}, TenantID => $TenantID, RequestID => $ID );
            if ( $Result->{Success} && @{ $Result->{Data} } ) {
                $Data->{Commitment} = $Result->{Data}->[0];
                $Data->{Commitments} = $Result->{Data};
            }
        }
        push @Data, $Data;
    }
    return { Success => 1, Data => \@Data };
}

sub ApprovalDecide {
    my ( $Self, %Param ) = @_;
    return $Self->_TransactionRun( Code => sub { return $Self->_ApprovalDecide(%Param) } );
}

sub _ApprovalDecide {
    my ( $Self, %Param ) = @_;
    return $Self->_Error('REQUEST_DISABLED') if !$Kernel::OM->Get('Kernel::Config')->Get('D724::Request::Enabled');
    return $Self->_Error('REQUEST_ID_INVALID') if !$Self->_PositiveInteger( $Param{RequestID} );
    return $Self->_Error('DECISION_INVALID') if ( $Param{Decision} // q{} ) !~ m{\A(?:approved|rejected)\z}smx;
    return $Self->_Error('VERSION_REQUIRED') if !$Self->_PositiveInteger( $Param{ExpectedVersion} );
    return $Self->_Error('COMMENT_INVALID') if length( $Param{Comment} // q{} ) > 4000;
    my $Context = $Self->_AgentAuthorize( %Param, Action => 'case.update' );
    return $Context if !$Context->{Success};
    my $Request = $Self->_RequestAggregate( TenantID => $Param{TenantID}, RequestID => $Param{RequestID} );
    return $Self->_Error('NOT_FOUND') if !$Request;
    return $Self->_Error('TRANSITION_INVALID') if $Request->{Status} ne 'awaiting_approval';
    my ($Approval) = grep { $_->{Status} eq 'pending' } @{ $Request->{Approvals} };
    return $Self->_Error('NO_PENDING_APPROVAL') if !$Approval;
    return $Self->_Error('VERSION_CONFLICT') if $Approval->{Version} != $Param{ExpectedVersion};
    my %Roles = map { $_ => 1 } @{ $Context->{Subject}->{RoleBindings}->{ $Param{TenantID} } // [] };
    return $Self->_Error('APPROVER_ROLE_REQUIRED') if !$Roles{ $Approval->{ApproverRole} };
    my $Actor = $Context->{Subject}->{ID};
    my @Values = ( $Param{Decision}, $Param{Comment} // q{}, $Actor, $Param{TenantID}, $Approval->{ApprovalID}, $Param{ExpectedVersion} );
    my @Bind = map { \$_ } @Values;
    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');
    return $Self->_Error('DATABASE_ERROR') if !$DBObject->Do(
        SQL => 'UPDATE d724_request_approval SET status = ?, decision_comment = ?, decision_time = current_timestamp, decision_by = ?, version = version + 1 '
            . 'WHERE tenant_id = ? AND id = ? AND version = ?', Bind => \@Bind,
    );
    my $UpdatedApproval = $Self->_ApprovalRowGet( TenantID => $Param{TenantID}, ApprovalID => $Approval->{ApprovalID} );
    return $Self->_Error('VERSION_CONFLICT')
        if !$UpdatedApproval || $UpdatedApproval->{Version} != $Param{ExpectedVersion} + 1
        || $UpdatedApproval->{Status} ne $Param{Decision};
    my $RequestStatus = $Param{Decision} eq 'approved' ? 'in_fulfillment' : 'rejected';
    my $TaskStatus    = $Param{Decision} eq 'approved' ? 'pending' : 'cancelled';
    my @RequestValues = ( $RequestStatus, $Actor, $Param{TenantID}, $Param{RequestID} );
    my @RequestBind = map { \$_ } @RequestValues;
    return $Self->_Error('DATABASE_ERROR') if !$DBObject->Do(
        SQL => "UPDATE d724_request SET status = ?, version = version + 1, change_time = current_timestamp, change_by = ? WHERE tenant_id = ? AND id = ? AND status = 'awaiting_approval'",
        Bind => \@RequestBind,
    );
    my $Commitment = $Self->_CommitmentObject();
    if ($Commitment) {
        my $Current = $Commitment->AgentGetByRequest( UserID => $Param{UserID}, TenantID => $Param{TenantID}, RequestID => $Param{RequestID} );
        if ( $Current->{Success} ) {
            my $Synced = $Commitment->Signal(
                UserID => $Param{UserID}, TenantID => $Param{TenantID}, RequestID => $Param{RequestID},
                PolicyKey => $Current->{Data}->{Policy}->{Key}, Signal => $Param{Decision} eq 'rejected' ? 'request_rejected' : 'request_approved',
                RequestStatus => $RequestStatus,
            );
            return $Self->_Error('COMMITMENT_SYNC_FAILED') if !$Synced->{Success};
            if ( $Param{Decision} eq 'approved' ) {
                my $StatusSync = $Commitment->SyncAllRequestStatus(
                    UserID => $Param{UserID}, TenantID => $Param{TenantID}, RequestID => $Param{RequestID}, RequestStatus => $RequestStatus,
                );
                return $Self->_Error('COMMITMENT_SYNC_FAILED') if !$StatusSync->{Success};
            }
        }
    }
    my @TaskValues = ( $TaskStatus, $Actor, $Param{TenantID}, $Param{RequestID} );
    my @TaskBind = map { \$_ } @TaskValues;
    $DBObject->Do(
        SQL => "UPDATE d724_request_task SET status = ?, version = version + 1, change_time = current_timestamp, change_by = ? WHERE tenant_id = ? AND request_id = ? AND status = 'blocked'",
        Bind => \@TaskBind,
    );
    my $Audited = $Self->_AuditRecord(
        TenantID => $Param{TenantID}, ActorID => $Actor, ActorType => 'agent', Action => 'request.' . $Param{Decision},
        ObjectType => 'request', ObjectID => $Param{RequestID}, CorrelationID => $Request->{RequestNumber},
        DedupeKey => "request:$Param{RequestID}:approval:$Approval->{ApprovalID}:$Param{ExpectedVersion}:$Param{Decision}",
        FromState => 'awaiting_approval', ToState => $RequestStatus,
        Details => { approval_id => $Approval->{ApprovalID}, approver_role => $Approval->{ApproverRole} },
    );
    return $Self->_Error('AUDIT_WRITE_FAILED') if !$Audited->{Success};
    return { Success => 1, Data => $Self->_RequestAggregate( TenantID => $Param{TenantID}, RequestID => $Param{RequestID} ) };
}

sub TaskUpdate {
    my ( $Self, %Param ) = @_;
    return $Self->_TransactionRun( Code => sub { return $Self->_TaskUpdate(%Param) } );
}

sub _TaskUpdate {
    my ( $Self, %Param ) = @_;
    return $Self->_Error('REQUEST_DISABLED') if !$Kernel::OM->Get('Kernel::Config')->Get('D724::Request::Enabled');
    return $Self->_Error('TASK_ID_INVALID') if !$Self->_PositiveInteger( $Param{TaskID} );
    return $Self->_Error('TASK_STATUS_INVALID') if ( $Param{Status} // q{} ) !~ m{\A(?:in_progress|completed|failed)\z}smx;
    return $Self->_Error('VERSION_REQUIRED') if !$Self->_PositiveInteger( $Param{ExpectedVersion} );
    return $Self->_Error('COMMENT_INVALID') if length( $Param{Comment} // q{} ) > 4000;
    my $Context = $Self->_AgentAuthorize( %Param, Action => 'case.update' );
    return $Context if !$Context->{Success};
    my $Task = $Self->_TaskRowGet( TenantID => $Param{TenantID}, TaskID => $Param{TaskID} );
    return $Self->_Error('NOT_FOUND') if !$Task;
    return $Self->_Error('VERSION_CONFLICT') if $Task->{Version} != $Param{ExpectedVersion};
    my %Allowed = (
        pending     => { in_progress => 1, completed => 1, failed => 1 },
        in_progress => { completed => 1, failed => 1 },
    );
    return $Self->_Error('TRANSITION_INVALID')
        if !$Allowed{ $Task->{Status} } || !$Allowed{ $Task->{Status} }->{ $Param{Status} };
    my $Actor = $Context->{Subject}->{ID};
    my @Values = ( $Param{Status}, $Param{Comment} // q{}, $Actor, $Param{TenantID}, $Param{TaskID}, $Param{ExpectedVersion} );
    my @Bind = map { \$_ } @Values;
    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');
    return $Self->_Error('DATABASE_ERROR') if !$DBObject->Do(
        SQL => 'UPDATE d724_request_task SET status = ?, result_comment = ?, version = version + 1, change_time = current_timestamp, change_by = ? '
            . 'WHERE tenant_id = ? AND id = ? AND version = ?', Bind => \@Bind,
    );
    my $UpdatedTask = $Self->_TaskRowGet( TenantID => $Param{TenantID}, TaskID => $Param{TaskID} );
    return $Self->_Error('VERSION_CONFLICT')
        if !$UpdatedTask || $UpdatedTask->{Version} != $Param{ExpectedVersion} + 1
        || $UpdatedTask->{Status} ne $Param{Status};
    my $RequestBefore = $Self->_RequestAggregate( TenantID => $Param{TenantID}, RequestID => $Task->{RequestID} );
    my $TaskAudit = $Self->_AuditRecord(
        TenantID => $Param{TenantID}, ActorID => $Actor, ActorType => 'agent', Action => 'task.status_changed',
        ObjectType => 'request_task', ObjectID => $Param{TaskID}, CorrelationID => $RequestBefore->{RequestNumber},
        DedupeKey => "request-task:$Param{TaskID}:version:" . ( $Param{ExpectedVersion} + 1 ),
        FromState => $Task->{Status}, ToState => $Param{Status}, Details => { request_id => $Task->{RequestID} },
    );
    return $Self->_Error('AUDIT_WRITE_FAILED') if !$TaskAudit->{Success};
    if ( $Param{Status} eq 'failed' ) {
        my @RequestValues = ( $Actor, $Param{TenantID}, $Task->{RequestID} );
        my @RequestBind = map { \$_ } @RequestValues;
        return $Self->_Error('DATABASE_ERROR') if !$DBObject->Do(
            SQL => "UPDATE d724_request SET status = 'fulfillment_failed', version = version + 1, change_time = current_timestamp, change_by = ? WHERE tenant_id = ? AND id = ? AND status = 'in_fulfillment'",
            Bind => \@RequestBind,
        );
        my $Synced = $Self->_CommitmentSync(
            UserID => $Param{UserID}, TenantID => $Param{TenantID}, RequestID => $Task->{RequestID}, RequestStatus => 'fulfillment_failed',
        );
        return $Self->_Error('COMMITMENT_SYNC_FAILED') if !$Synced->{Success};
    }
    if ( $Param{Status} eq 'completed' ) {
        my $RequestID = $Task->{RequestID};
        $DBObject->Prepare(
            SQL => "SELECT COUNT(*) FROM d724_request_task WHERE tenant_id = ? AND request_id = ? AND status <> 'completed'",
            Bind => [ \$Param{TenantID}, \$RequestID ],
        );
        my ($Remaining) = $DBObject->FetchrowArray();
        if (!$Remaining) {
            my @RequestValues = ( $Actor, $Param{TenantID}, $RequestID );
            my @RequestBind = map { \$_ } @RequestValues;
            return $Self->_Error('DATABASE_ERROR') if !$DBObject->Do(
                SQL => "UPDATE d724_request SET status = 'fulfilled', version = version + 1, change_time = current_timestamp, change_by = ? WHERE tenant_id = ? AND id = ?",
                Bind => \@RequestBind,
            );
            my $Commitment = $Self->_CommitmentObject();
            if ($Commitment) {
                my $Current = $Commitment->AgentGetByRequest( UserID => $Param{UserID}, TenantID => $Param{TenantID}, RequestID => $RequestID );
                if ( $Current->{Success} ) {
                    my $Completed = $Commitment->Signal(
                        UserID => $Param{UserID}, TenantID => $Param{TenantID}, RequestID => $RequestID,
                        PolicyKey => $Current->{Data}->{Policy}->{Key}, Signal => 'request_fulfilled', RequestStatus => 'fulfilled',
                    );
                    return $Self->_Error('COMMITMENT_SYNC_FAILED') if !$Completed->{Success};
                }
            }
            my $RequestAudit = $Self->_AuditRecord(
                TenantID => $Param{TenantID}, ActorID => $Actor, ActorType => 'agent', Action => 'request.fulfilled',
                ObjectType => 'request', ObjectID => $RequestID, CorrelationID => $RequestBefore->{RequestNumber},
                DedupeKey => "request:$RequestID:fulfilled",
                FromState => 'in_fulfillment', ToState => 'fulfilled', Details => { final_task_id => $Param{TaskID} },
            );
            return $Self->_Error('AUDIT_WRITE_FAILED') if !$RequestAudit->{Success};
        }
    }
    return { Success => 1, Data => $Self->_RequestAggregate( TenantID => $Param{TenantID}, RequestID => $Task->{RequestID} ) };
}

sub ResponseRecord {
    my ( $Self, %Param ) = @_;
    return $Self->_TransactionRun( Code => sub { return $Self->_ResponseRecord(%Param) } );
}

sub _ResponseRecord {
    my ( $Self, %Param ) = @_;
    return $Self->_Error('REQUEST_DISABLED') if !$Kernel::OM->Get('Kernel::Config')->Get('D724::Request::Enabled');
    return $Self->_Error('REQUEST_ID_INVALID') if !$Self->_PositiveInteger( $Param{RequestID} );
    my $Context = $Self->_AgentAuthorize( %Param, Action => 'case.update' );
    return $Context if !$Context->{Success};
    my $Request = $Self->_RequestAggregate( TenantID => $Param{TenantID}, RequestID => $Param{RequestID} );
    return $Self->_Error('NOT_FOUND') if !$Request;
    return $Self->_Error('TRANSITION_INVALID') if $Request->{Status} =~ m{\A(?:fulfilled|rejected)\z}smx;
    my $Commitment = $Self->_CommitmentObject();
    return $Self->_Error('COMMITMENT_NOT_AVAILABLE') if !$Commitment;
    my $Current = $Commitment->AgentGetByRequest( UserID => $Param{UserID}, TenantID => $Param{TenantID}, RequestID => $Param{RequestID} );
    return $Self->_Error('COMMITMENT_NOT_FOUND') if !$Current->{Success};
    my $Result = $Commitment->Signal(
        UserID => $Param{UserID}, TenantID => $Param{TenantID}, RequestID => $Param{RequestID},
        PolicyKey => $Current->{Data}->{Policy}->{Key}, Signal => 'first_response', RequestStatus => $Request->{Status}, At => $Param{At},
    );
    return $Self->_Error('COMMITMENT_SYNC_FAILED') if !$Result->{Success};
    my $Audited = $Self->_AuditRecord(
        TenantID => $Param{TenantID}, ActorID => $Context->{Subject}->{ID}, ActorType => 'agent', Action => 'request.first_response',
        ObjectType => 'request', ObjectID => $Param{RequestID}, CorrelationID => $Request->{RequestNumber},
        DedupeKey => "request:$Param{RequestID}:first-response",
        FromState => $Request->{Status}, ToState => $Request->{Status}, Details => {},
    );
    return $Self->_Error('AUDIT_WRITE_FAILED') if !$Audited->{Success};
    return { Success => 1, Data => $Result->{Data} };
}

sub _AgentAuthorize {
    my ( $Self, %Param ) = @_;
    my $Context = $Kernel::OM->Get('Kernel::System::D724::TenantDirectory')->ContextGet( UserID => $Param{UserID} );
    return $Context if !$Context->{Success};
    my $Decision = $Kernel::OM->Get('Kernel::System::D724::TenantGuard')->DecisionGet(
        Subject => $Context->{Subject}, Resource => { TenantID => $Param{TenantID} }, Action => $Param{Action},
    );
    return $Self->_Error( 'FORBIDDEN', $Decision->{Reason} ) if !$Decision->{Allowed};
    return { Success => 1, Subject => $Context->{Subject} };
}

sub _AnswersValidate {
    my ( $Self, %Param ) = @_;
    return $Self->_Error('ANSWERS_INVALID') if ref $Param{Answers} ne 'HASH';
    my %Fields = map { $_->{key} => $_ } @{ $Param{Schema}->{fields} };
    for my $Key ( keys %{ $Param{Answers} } ) {
        return $Self->_Error('ANSWER_UNKNOWN') if !$Fields{$Key};
    }
    my %Normalized;
    for my $Key ( sort keys %Fields ) {
        my $Field = $Fields{$Key};
        my $Value = $Param{Answers}->{$Key};
        my $Missing = !defined $Value || ( !ref $Value && $Value eq q{} ) || ( ref $Value eq 'ARRAY' && !@{$Value} );
        return $Self->_Error('ANSWER_REQUIRED') if $Field->{required} && $Missing;
        next if $Missing;
        if ( $Field->{type} eq 'multiselect' ) {
            return $Self->_Error('ANSWER_TYPE_INVALID') if ref $Value ne 'ARRAY' || @{$Value} > 100;
            my %Allowed = map { $_->{value} => 1 } @{ $Field->{options} };
            return $Self->_Error('ANSWER_OPTION_INVALID') if grep { !$Allowed{$_} } @{$Value};
            $Normalized{$Key} = [ @{$Value} ];
            next;
        }
        return $Self->_Error('ANSWER_TYPE_INVALID') if ref $Value;
        return $Self->_Error('ANSWER_TOO_LONG') if length $Value > 4000;
        if ( $Field->{type} eq 'select' ) {
            my %Allowed = map { $_->{value} => 1 } @{ $Field->{options} };
            return $Self->_Error('ANSWER_OPTION_INVALID') if !$Allowed{$Value};
        }
        return $Self->_Error('ANSWER_TYPE_INVALID') if $Field->{type} eq 'checkbox' && $Value !~ m{\A[01]\z}smx;
        return $Self->_Error('ANSWER_TYPE_INVALID') if $Field->{type} eq 'number' && $Value !~ m{\A-?(?:\d+|\d*\.\d+)\z}smx;
        return $Self->_Error('ANSWER_TYPE_INVALID') if $Field->{type} eq 'email' && $Value !~ m{\A[^\s\@]+\@[^\s\@]+\.[^\s\@]+\z}smx;
        return $Self->_Error('ANSWER_TYPE_INVALID') if $Field->{type} eq 'date' && $Value !~ m{\A\d{4}-\d{2}-\d{2}\z}smx;
        return $Self->_Error('ANSWER_TYPE_INVALID') if $Field->{type} eq 'datetime' && $Value !~ m{\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(?::\d{2})?\z}smx;
        $Normalized{$Key} = "$Value";
    }
    return { Success => 1, Data => \%Normalized };
}

sub _WorkflowNormalize {
    my ( $Self, %Param ) = @_;
    my $Workflow = $Param{Schema}->{workflow} // {};
    my $Normalized = {
        approval => $Workflow->{approval} // { required => 0 },
        fulfillment => $Workflow->{fulfillment} // [ { key => 'fulfill', name => 'Fulfill request', type => 'manual' } ],
    };
    if ( $Workflow->{commitment} ) {
        my $Definition = $Workflow->{commitment};
        my $PolicyKey = $Definition->{default_policy_key} // $Definition->{policy_key};
        my $EntitlementKey = 'default';
        for my $Entitlement ( @{ $Definition->{entitlements} // [] } ) {
            my $Value = $Param{Answers}->{ $Entitlement->{answer_key} };
            next if ref $Value || !defined $Value || "$Value" ne "$Entitlement->{equals}";
            $PolicyKey = $Entitlement->{policy_key}; $EntitlementKey = $Entitlement->{key}; last;
        }
        $Normalized->{commitment} = { policy_key => $PolicyKey, entitlement_key => $EntitlementKey };
    }
    return $Normalized;
}

sub _CommitmentObject {
    my ($Self) = @_;
    return if !$Kernel::OM->Get('Kernel::Config')->Get('D724::Commitment::Enabled');
    my $Object = eval { $Kernel::OM->Get('Kernel::System::D724::Commitment') };
    return $@ ? undef : $Object;
}

sub _AuditRecord {
    my ( $Self, %Param ) = @_;
    my $Audit = eval { $Kernel::OM->Get('Kernel::System::D724::Audit') };
    return { Success => 0, Error => 'AUDIT_NOT_AVAILABLE' } if $@ || !$Audit;
    return $Audit->Record( %Param, Outcome => 'success' );
}

sub _TransactionRun {
    my ( $Self, %Param ) = @_;
    return $Self->_Error('TRANSACTION_CODE_INVALID') if ref $Param{Code} ne 'CODE';
    my $DB = $Kernel::OM->Get('Kernel::System::DB');
    my $Handle = $DB->Connect();
    return $Self->_Error('TRANSACTION_CONNECTION_FAILED') if !$Handle;

    # OTOBO unit tests and callers may already own the surrounding transaction.
    # In that case this operation joins it; the outer owner remains responsible
    # for commit/rollback. Normal web and console requests enter with AutoCommit.
    return $Param{Code}->() if !$Handle->{AutoCommit};

    my $Result;
    my $OK = eval {
        die "TRANSACTION_START_FAILED\n" if !$DB->BeginWork();
        $Result = $Param{Code}->();
        die "TRANSACTION_RESULT_INVALID\n" if ref $Result ne 'HASH' || !exists $Result->{Success};
        if ( $Result->{Success} ) {
            die "TRANSACTION_COMMIT_FAILED\n" if !$Handle->commit();
        }
        else {
            die "TRANSACTION_ROLLBACK_FAILED\n" if !$DB->Rollback();
        }
        1;
    };
    if ( !$OK ) {
        my $Failure = $@ || 'TRANSACTION_FAILED';
        eval { $DB->Rollback() } if !$Handle->{AutoCommit};
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error', Message => "D724 request transaction failed: $Failure",
        );
        return $Self->_Error('TRANSACTION_FAILED');
    }
    return $Result;
}

sub _AuditRequestCreated {
    my ( $Self, %Param ) = @_;
    my $Request = $Param{Request};
    return { Success => 0, Error => 'REQUEST_NOT_AVAILABLE' } if ref $Request ne 'HASH';
    my $Workflow = $Request->{Workflow};
    $Workflow = {} if ref $Workflow ne 'HASH';
    my $Commitment = $Workflow->{commitment};
    $Commitment = {} if ref $Commitment ne 'HASH';
    return $Self->_AuditRecord(
        TenantID => $Param{TenantID}, ActorID => $Param{ActorID}, ActorType => 'customer',
        Action => 'request.created', ObjectType => 'request', ObjectID => $Request->{RequestID},
        CorrelationID => $Request->{RequestNumber}, DedupeKey => "request:$Request->{RequestID}:created",
        FromState => 'initializing', ToState => $Request->{Status},
        Details => {
            catalog_item_id => $Request->{CatalogItemID},
            entitlement_key => $Commitment->{entitlement_key} // q{},
        },
    );
}

sub _CommitmentSync {
    my ( $Self, %Param ) = @_;
    my $Commitment = $Self->_CommitmentObject();
    return { Success => 1, NoChange => 1 } if !$Commitment;
    my $Current = $Commitment->AgentGetByRequest( UserID => $Param{UserID}, TenantID => $Param{TenantID}, RequestID => $Param{RequestID} );
    return { Success => 1, NoChange => 1 } if !$Current->{Success};
    return $Commitment->SyncAllRequestStatus(%Param);
}

sub _RequestByIdempotency {
    my ( $Self, %Param ) = @_;
    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');
    $DBObject->Prepare(
        SQL => 'SELECT id, payload_hash FROM d724_request WHERE tenant_id = ? AND requester_id = ? AND idempotency_key = ?',
        Bind => [ \$Param{TenantID}, \$Param{RequesterID}, \$Param{IdempotencyKey} ], Limit => 1,
    );
    my ( $ID, $Hash ) = $DBObject->FetchrowArray();
    return if !$ID;
    return { RequestID => $ID, PayloadHash => $Hash };
}

sub _RequestAggregate {
    my ( $Self, %Param ) = @_;
    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');
    $DBObject->Prepare(
        SQL => 'SELECT id, request_number, tenant_id, catalog_item_id, requester_id, status, version, answers_json, workflow_json, payload_hash, create_time, create_by, change_time, change_by '
            . 'FROM d724_request WHERE tenant_id = ? AND id = ?', Bind => [ \$Param{TenantID}, \$Param{RequestID} ], Limit => 1,
    );
    my @Row = $DBObject->FetchrowArray();
    return if !@Row;
    my @Columns = qw(RequestID RequestNumber TenantID CatalogItemID RequesterID Status Version AnswersJSON WorkflowJSON PayloadHash CreateTime CreateBy ChangeTime ChangeBy);
    my %Data; @Data{@Columns} = @Row;
    my $JSON = $Kernel::OM->Get('Kernel::System::JSON');
    $Data{Answers}  = $JSON->Decode( Data => delete $Data{AnswersJSON} );
    $Data{Workflow} = $JSON->Decode( Data => delete $Data{WorkflowJSON} );
    $Data{Approvals} = $Self->_ApprovalsGet(%Param);
    $Data{Tasks}     = $Self->_TasksGet(%Param);
    return \%Data;
}

sub _ApprovalsGet {
    my ( $Self, %Param ) = @_;
    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');
    $DBObject->Prepare(
        SQL => 'SELECT id, sequence_no, approver_role, status, decision_comment, version, decision_time, decision_by FROM d724_request_approval WHERE tenant_id = ? AND request_id = ? ORDER BY sequence_no',
        Bind => [ \$Param{TenantID}, \$Param{RequestID} ],
    );
    my @Data;
    while ( my @Row = $DBObject->FetchrowArray() ) {
        push @Data, { ApprovalID => $Row[0], Sequence => $Row[1], ApproverRole => $Row[2], Status => $Row[3], Comment => $Row[4], Version => $Row[5], DecisionTime => $Row[6], DecisionBy => $Row[7] };
    }
    return \@Data;
}

sub _TasksGet {
    my ( $Self, %Param ) = @_;
    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');
    $DBObject->Prepare(
        SQL => 'SELECT id, key_name, name, task_type, status, version, result_comment, assigned_group, change_time, change_by FROM d724_request_task WHERE tenant_id = ? AND request_id = ? ORDER BY id',
        Bind => [ \$Param{TenantID}, \$Param{RequestID} ],
    );
    my @Data;
    while ( my @Row = $DBObject->FetchrowArray() ) {
        push @Data, { TaskID => $Row[0], Key => $Row[1], Name => $Row[2], Type => $Row[3], Status => $Row[4], Version => $Row[5], Comment => $Row[6], AssignedGroup => $Row[7], ChangeTime => $Row[8], ChangeBy => $Row[9], RequestID => $Param{RequestID} };
    }
    return \@Data;
}

sub _TaskRowGet {
    my ( $Self, %Param ) = @_;
    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');
    $DBObject->Prepare(
        SQL => 'SELECT request_id, status, version FROM d724_request_task WHERE tenant_id = ? AND id = ?',
        Bind => [ \$Param{TenantID}, \$Param{TaskID} ], Limit => 1,
    );
    my @Row = $DBObject->FetchrowArray();
    return if !@Row;
    return { RequestID => $Row[0], Status => $Row[1], Version => $Row[2] };
}

sub _ApprovalRowGet {
    my ( $Self, %Param ) = @_;
    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');
    $DBObject->Prepare(
        SQL => 'SELECT status, version FROM d724_request_approval WHERE tenant_id = ? AND id = ?',
        Bind => [ \$Param{TenantID}, \$Param{ApprovalID} ], Limit => 1,
    );
    my @Row = $DBObject->FetchrowArray();
    return if !@Row;
    return { Status => $Row[0], Version => $Row[1] };
}

sub _InitializationFail {
    my ( $Self, %Param ) = @_;
    my @Values = ( $Param{Actor}, $Param{TenantID}, $Param{RequestID} );
    my @Bind = map { \$_ } @Values;
    $Kernel::OM->Get('Kernel::System::DB')->Do(
        SQL => "UPDATE d724_request SET status = 'submission_failed', change_time = current_timestamp, change_by = ? WHERE tenant_id = ? AND id = ?",
        Bind => \@Bind,
    );
    return $Self->_Error('INITIALIZATION_FAILED');
}

sub _PositiveInteger { return defined $_[1] && $_[1] =~ m{\A[1-9][0-9]*\z}smx ? 1 : 0 }
sub _Error {
    my ( $Self, $Code, $Reason ) = @_;
    my $Error = { Success => 0, Error => $Code };
    $Error->{Reason} = $Reason if defined $Reason;
    return $Error;
}

1;
