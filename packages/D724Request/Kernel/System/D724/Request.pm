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

our $VERSION = '0.1.2';
our @ObjectDependencies = (
    'Kernel::Config',
    'Kernel::System::D724::CatalogPortal',
    'Kernel::System::D724::TenantDirectory',
    'Kernel::System::D724::TenantGuard',
    'Kernel::System::DB',
    'Kernel::System::JSON',
);

sub new { return bless {}, $_[0] }

sub CustomerSubmit {
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
    my $Workflow = $Self->_WorkflowNormalize( Schema => $Schema );
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
        return { Success => 1, Data => $Self->_RequestAggregate( TenantID => $TenantID, RequestID => $Raced->{RequestID} ), IdempotentReplay => 1 };
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
        push @Data, $Self->_RequestAggregate( TenantID => $TenantID, RequestID => $ID );
    }
    return { Success => 1, Data => \@Data };
}

sub ApprovalDecide {
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
    $DBObject->Do(
        SQL => "UPDATE d724_request SET status = ?, version = version + 1, change_time = current_timestamp, change_by = ? WHERE tenant_id = ? AND id = ? AND status = 'awaiting_approval'",
        Bind => \@RequestBind,
    );
    my @TaskValues = ( $TaskStatus, $Actor, $Param{TenantID}, $Param{RequestID} );
    my @TaskBind = map { \$_ } @TaskValues;
    $DBObject->Do(
        SQL => "UPDATE d724_request_task SET status = ?, version = version + 1, change_time = current_timestamp, change_by = ? WHERE tenant_id = ? AND request_id = ? AND status = 'blocked'",
        Bind => \@TaskBind,
    );
    return { Success => 1, Data => $Self->_RequestAggregate( TenantID => $Param{TenantID}, RequestID => $Param{RequestID} ) };
}

sub TaskUpdate {
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
    if ( $Param{Status} eq 'failed' ) {
        my @RequestValues = ( $Actor, $Param{TenantID}, $Task->{RequestID} );
        my @RequestBind = map { \$_ } @RequestValues;
        $DBObject->Do(
            SQL => "UPDATE d724_request SET status = 'fulfillment_failed', version = version + 1, change_time = current_timestamp, change_by = ? WHERE tenant_id = ? AND id = ? AND status = 'in_fulfillment'",
            Bind => \@RequestBind,
        );
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
            $DBObject->Do(
                SQL => "UPDATE d724_request SET status = 'fulfilled', version = version + 1, change_time = current_timestamp, change_by = ? WHERE tenant_id = ? AND id = ?",
                Bind => \@RequestBind,
            );
        }
    }
    return { Success => 1, Data => $Self->_RequestAggregate( TenantID => $Param{TenantID}, RequestID => $Task->{RequestID} ) };
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
    return {
        approval => $Workflow->{approval} // { required => 0 },
        fulfillment => $Workflow->{fulfillment} // [ { key => 'fulfill', name => 'Fulfill request', type => 'manual' } ],
    };
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
        SQL => 'SELECT id, key_name, name, task_type, status, version, result_comment, change_time, change_by FROM d724_request_task WHERE tenant_id = ? AND request_id = ? ORDER BY id',
        Bind => [ \$Param{TenantID}, \$Param{RequestID} ],
    );
    my @Data;
    while ( my @Row = $DBObject->FetchrowArray() ) {
        push @Data, { TaskID => $Row[0], Key => $Row[1], Name => $Row[2], Type => $Row[3], Status => $Row[4], Version => $Row[5], Comment => $Row[6], ChangeTime => $Row[7], ChangeBy => $Row[8], RequestID => $Param{RequestID} };
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
