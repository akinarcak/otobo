# --
# D724 ESM is an enterprise service management platform based on OTOBO.
# Copyright (C) 2026 Data Market Bilgi Hizmetleri A.S.
# SPDX-License-Identifier: GPL-3.0-only
# --

package Kernel::System::D724::Commitment;

use v5.24;
use strict;
use warnings;
use Digest::SHA qw(sha256_hex);

our $VERSION = '0.3.0';
our @ObjectDependencies = (
    'Kernel::Config',
    'Kernel::System::D724::TenantDirectory',
    'Kernel::System::D724::TenantGuard',
    'Kernel::System::DB',
    'Kernel::System::JSON',
);

sub new { return bless {}, $_[0] }

sub PolicyCreate {
    my ( $Self, %Param ) = @_;
    my $Auth = $Self->_PolicyAuthorize(%Param);
    return $Auth if !$Auth->{Success};
    my $Valid = $Self->_PolicyValidate(%Param);
    return $Valid if !$Valid->{Success};
    my $Existing = $Self->_PolicyRowGet( TenantID => $Param{TenantID}, Key => $Param{Key} );
    return $Self->_Error('KEY_EXISTS') if $Existing;
    my $PauseJSON = $Kernel::OM->Get('Kernel::System::JSON')->Encode( Data => $Param{PauseStatuses} // [], SortKeys => 1 );
    my @Values = ( @Param{qw(TenantID Key Name CalendarID TargetSeconds WarningPercent)}, $PauseJSON, $Param{Status} // 'active', $Param{UserID}, $Param{UserID} );
    my @Bind = map { \$_ } @Values;
    my $OK = $Kernel::OM->Get('Kernel::System::DB')->Do(
        SQL => 'INSERT INTO d724_commitment_policy (tenant_id, key_name, name, calendar_id, target_seconds, warning_percent, pause_statuses_json, status, version, create_time, create_by, change_time, change_by) '
            . 'VALUES (?, ?, ?, ?, ?, ?, ?, ?, 1, current_timestamp, ?, current_timestamp, ?)', Bind => \@Bind,
    );
    return $Self->_Error('DATABASE_ERROR') if !$OK;
    my $Data = $Self->_PolicyRowGet( TenantID => $Param{TenantID}, Key => $Param{Key} );
    return $Self->_Error('DATABASE_ERROR') if !$Data;
    my $Objectives = $Self->_PolicyObjectivesReplace(
        TenantID => $Param{TenantID}, PolicyID => $Data->{PolicyID}, Objectives => $Param{Objectives},
    );
    return $Objectives if !$Objectives->{Success};
    $Data = $Self->_PolicyRowGet( TenantID => $Param{TenantID}, PolicyID => $Data->{PolicyID} );
    return { Success => 1, Data => $Data };
}

sub PolicyUpdate {
    my ( $Self, %Param ) = @_;
    my $Auth = $Self->_PolicyAuthorize(%Param);
    return $Auth if !$Auth->{Success};
    return $Self->_Error('VERSION_REQUIRED') if !$Self->_PositiveInteger( $Param{ExpectedVersion} );
    my $Current = $Self->_PolicyRowGet( TenantID => $Param{TenantID}, PolicyID => $Param{PolicyID} );
    return $Self->_Error('NOT_FOUND') if !$Current;
    return $Self->_Error('VERSION_CONFLICT') if $Current->{Version} != $Param{ExpectedVersion};
    for my $Pair ( [ Name => 'Name' ], [ CalendarID => 'CalendarID' ], [ TargetSeconds => 'TargetSeconds' ], [ WarningPercent => 'WarningPercent' ], [ PauseStatuses => 'PauseStatuses' ], [ Status => 'Status' ] ) {
        $Param{ $Pair->[0] } //= $Current->{ $Pair->[1] };
    }
    $Param{Key} = $Current->{Key};
    my $Valid = $Self->_PolicyValidate(%Param);
    return $Valid if !$Valid->{Success};
    my $PauseJSON = $Kernel::OM->Get('Kernel::System::JSON')->Encode( Data => $Param{PauseStatuses}, SortKeys => 1 );
    my @Values = ( @Param{qw(Name CalendarID TargetSeconds WarningPercent)}, $PauseJSON, $Param{Status}, $Param{UserID}, $Param{TenantID}, $Param{PolicyID}, $Param{ExpectedVersion} );
    my @Bind = map { \$_ } @Values;
    my $OK = $Kernel::OM->Get('Kernel::System::DB')->Do(
        SQL => 'UPDATE d724_commitment_policy SET name = ?, calendar_id = ?, target_seconds = ?, warning_percent = ?, pause_statuses_json = ?, status = ?, '
            . 'version = version + 1, change_time = current_timestamp, change_by = ? WHERE tenant_id = ? AND id = ? AND version = ?', Bind => \@Bind,
    );
    return $Self->_Error('DATABASE_ERROR') if !$OK;
    my $Updated = $Self->_PolicyRowGet( TenantID => $Param{TenantID}, PolicyID => $Param{PolicyID} );
    return $Self->_Error('VERSION_CONFLICT') if !$Updated || $Updated->{Version} != $Param{ExpectedVersion} + 1;
    if ( exists $Param{Objectives} ) {
        my $Objectives = $Self->_PolicyObjectivesReplace(
            TenantID => $Param{TenantID}, PolicyID => $Param{PolicyID}, Objectives => $Param{Objectives},
        );
        return $Objectives if !$Objectives->{Success};
        $Updated = $Self->_PolicyRowGet( TenantID => $Param{TenantID}, PolicyID => $Param{PolicyID} );
    }
    return { Success => 1, Data => $Updated };
}

sub PolicyGet {
    my ( $Self, %Param ) = @_;
    my $Auth = $Self->_PolicyAuthorize( %Param, ReadOnly => 1 );
    return $Auth if !$Auth->{Success};
    my $Data = $Self->_PolicyRowGet(%Param);
    return $Self->_Error('NOT_FOUND') if !$Data;
    return { Success => 1, Data => $Data };
}

sub PolicyList {
    my ( $Self, %Param ) = @_;
    my $Auth = $Self->_PolicyAuthorize( %Param, ReadOnly => 1 );
    return $Auth if !$Auth->{Success};
    my $TenantID = $Param{TenantID};
    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');
    $DBObject->Prepare( SQL => 'SELECT id FROM d724_commitment_policy WHERE tenant_id = ? ORDER BY key_name', Bind => [ \$TenantID ], Limit => 500 );
    my @Data;
    while ( my ($ID) = $DBObject->FetchrowArray() ) { push @Data, $Self->_PolicyRowGet( TenantID => $TenantID, PolicyID => $ID ) }
    return { Success => 1, Data => \@Data };
}

sub StartAll {
    my ( $Self, %Param ) = @_;
    my $Policy = $Self->_PolicyRowGet( TenantID => $Param{TenantID}, Key => $Param{PolicyKey} );
    return $Self->_Error('POLICY_NOT_FOUND') if !$Policy || $Policy->{Status} ne 'active';
    my @Objectives = @{ $Policy->{Objectives} // [] };
    @Objectives = ( $Self->_LegacyObjective($Policy) ) if !@Objectives;
    my @Started;
    for my $Objective (@Objectives) {
        next if $Objective->{start_signal} ne ( $Param{Signal} // 'request_created' );
        my $Result = $Self->Start( %Param, Objective => $Objective );
        return $Result if !$Result->{Success};
        push @Started, $Result->{Data};
    }
    return { Success => 1, Data => \@Started };
}

sub Signal {
    my ( $Self, %Param ) = @_;
    return $Self->_Error('SIGNAL_INVALID') if ( $Param{Signal} // q{} ) !~ m{\A(?:request_created|request_approved|first_response|request_fulfilled|request_rejected)\z}smx;
    my $Auth = $Self->_AgentAuthorize( %Param, Action => 'case.update' );
    return $Auth if !$Auth->{Success};
    my $Policy = $Self->_PolicyRowGet( TenantID => $Param{TenantID}, Key => $Param{PolicyKey} );
    return $Self->_Error('POLICY_NOT_FOUND') if !$Policy;
    my @Objectives = @{ $Policy->{Objectives} // [] };
    @Objectives = ( $Self->_LegacyObjective($Policy) ) if !@Objectives;
    my ( @Started, @Stopped );
    for my $Objective (@Objectives) {
        my $Existing = $Self->_InstanceRowGet(
            TenantID => $Param{TenantID}, RequestID => $Param{RequestID}, ObjectiveKey => $Objective->{key},
        );
        if ( !$Existing && $Objective->{start_signal} eq $Param{Signal} ) {
            my $Result = $Self->Start(
                TenantID => $Param{TenantID}, RequestID => $Param{RequestID}, PolicyKey => $Param{PolicyKey},
                Objective => $Objective, Actor => $Auth->{Subject}->{ID}, StartTime => $Param{At}, RequestStatus => $Param{RequestStatus},
            );
            return $Result if !$Result->{Success};
            push @Started, $Result->{Data};
            $Existing = $Result->{Data};
        }
        next if !$Existing || $Existing->{Status} =~ m{\A(?:met|breached|cancelled)\z}smx;
        next if $Objective->{stop_signal} ne $Param{Signal} && $Param{Signal} !~ m{\A(?:request_rejected|request_fulfilled)\z}smx;
        my $Result = $Param{Signal} eq 'request_rejected'
            ? $Self->Cancel(
                UserID => $Param{UserID}, TenantID => $Param{TenantID}, CommitmentID => $Existing->{CommitmentID},
                ExpectedVersion => $Existing->{Version}, At => $Param{At}, Reason => 'signal:request_rejected',
            )
            : $Self->Complete(
                UserID => $Param{UserID}, TenantID => $Param{TenantID}, CommitmentID => $Existing->{CommitmentID},
                ExpectedVersion => $Existing->{Version}, At => $Param{At}, Reason => 'signal:' . $Param{Signal},
            );
        return $Result if !$Result->{Success};
        push @Stopped, $Result->{Data};
    }
    return { Success => 1, Data => { Started => \@Started, Stopped => \@Stopped } };
}

sub Start {
    my ( $Self, %Param ) = @_;
    return $Self->_Error('COMMITMENT_DISABLED') if !$Self->_Enabled();
    return $Self->_Error('REQUEST_ID_INVALID') if !$Self->_PositiveInteger( $Param{RequestID} );
    return $Self->_Error('ACTOR_INVALID') if !defined $Param{Actor} || !length $Param{Actor} || length $Param{Actor} > 128;
    my $Policy = $Self->_PolicyRowGet( TenantID => $Param{TenantID}, Key => $Param{PolicyKey} );
    return $Self->_Error('POLICY_NOT_FOUND') if !$Policy || $Policy->{Status} ne 'active';
    return $Self->_Error('REQUEST_NOT_FOUND') if !$Self->_RequestExists( TenantID => $Param{TenantID}, RequestID => $Param{RequestID} );
    my $Objective = $Param{Objective} // $Self->_LegacyObjective($Policy);
    my $ObjectiveValid = $Self->_ObjectiveValidate( Objective => $Objective );
    return $ObjectiveValid if !$ObjectiveValid->{Success};
    my $Existing = $Self->_InstanceRowGet( TenantID => $Param{TenantID}, RequestID => $Param{RequestID}, ObjectiveKey => $Objective->{key} );
    return { Success => 1, Data => $Self->_Aggregate( %{$Existing} ), IdempotentReplay => 1 } if $Existing && $Existing->{PolicyID} == $Policy->{PolicyID};
    return $Self->_Error('REQUEST_COMMITMENT_EXISTS') if $Existing;
    my $Start = $Self->_TimeNormalize( $Param{StartTime} );
    return $Self->_Error('TIME_INVALID') if !$Start;
    my $Due = $Self->_Destination( StartTime => $Start, Seconds => $Objective->{target_seconds}, CalendarID => $Policy->{CalendarID} );
    my $WarningSeconds = int( $Objective->{target_seconds} * $Objective->{warning_percent} / 100 );
    my $Warning = $Self->_Destination( StartTime => $Start, Seconds => $WarningSeconds, CalendarID => $Policy->{CalendarID} );
    return $Self->_Error('CALENDAR_CALCULATION_FAILED') if !$Due || !$Warning;
    my %Pause = map { $_ => 1 } @{ $Policy->{PauseStatuses} };
    my $InitialStatus = $Pause{ $Param{RequestStatus} // q{} } ? 'paused' : 'running';
    my $RunningSince = $InitialStatus eq 'running' ? $Start : undef;
    my $PausedAt     = $InitialStatus eq 'paused'  ? $Start : undef;
    my $ActionsJSON = $Kernel::OM->Get('Kernel::System::JSON')->Encode( Data => $Objective->{escalation_actions} // [], SortKeys => 1 );
    my @Values = (
        $Param{TenantID}, $Param{RequestID}, $Policy->{PolicyID}, $InitialStatus,
        $Objective->{key}, $Objective->{type}, $Objective->{start_signal}, $Objective->{stop_signal}, $ActionsJSON,
        $Objective->{target_seconds}, 0, $Policy->{CalendarID}, $Objective->{warning_percent}, $Start, $RunningSince, $PausedAt, $Warning, $Due, $Param{Actor}, $Param{Actor},
    );
    my @Bind = map { \$_ } @Values;
    my $OK = $Kernel::OM->Get('Kernel::System::DB')->Do(
        SQL => 'INSERT INTO d724_commitment_instance (tenant_id, request_id, policy_id, status, objective_key, objective_type, start_signal, stop_signal, escalation_actions_json, '
            . 'target_seconds, consumed_seconds, calendar_id, warning_percent, start_time, running_since, paused_at, warning_time, due_time, version, create_time, create_by, change_time, change_by) '
            . 'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1, current_timestamp, ?, current_timestamp, ?)', Bind => \@Bind,
    );
    return $Self->_Error('DATABASE_ERROR') if !$OK;
    my $Instance = $Self->_InstanceRowGet( TenantID => $Param{TenantID}, RequestID => $Param{RequestID}, ObjectiveKey => $Objective->{key} );
    return $Self->_Error('DATABASE_ERROR') if !$Instance;
    $Self->_EventAdd( %{$Instance}, EventType => 'started', EventTime => $Start, FromStatus => q{}, ToStatus => $InitialStatus, Actor => $Param{Actor}, Reason => $InitialStatus eq 'paused' ? 'initial_request_status:' . $Param{RequestStatus} : q{} );
    return { Success => 1, Data => $Self->_Aggregate(%{$Instance}), IdempotentReplay => 0 };
}

sub AgentGetByRequest {
    my ( $Self, %Param ) = @_;
    my $Auth = $Self->_AgentAuthorize( %Param, Action => 'case.read' );
    return $Auth if !$Auth->{Success};
    my $Instance = defined $Param{CommitmentID}
        ? $Self->_InstanceRowGet( TenantID => $Param{TenantID}, CommitmentID => $Param{CommitmentID} )
        : $Self->_InstanceRowGet( TenantID => $Param{TenantID}, RequestID => $Param{RequestID} );
    return $Self->_Error('NOT_FOUND') if !$Instance;
    return { Success => 1, Data => $Self->_Aggregate(%{$Instance}) };
}

sub AgentListByRequest {
    my ( $Self, %Param ) = @_;
    my $Auth = $Self->_AgentAuthorize( %Param, Action => 'case.read' );
    return $Auth if !$Auth->{Success};
    my @Data = map { $Self->_Aggregate(%{$_}) } $Self->_InstancesByRequest( TenantID => $Param{TenantID}, RequestID => $Param{RequestID} );
    return { Success => 1, Data => \@Data };
}

sub Pause { my ( $Self, %Param ) = @_; return $Self->_Transition( %Param, Operation => 'pause' ) }
sub Resume { my ( $Self, %Param ) = @_; return $Self->_Transition( %Param, Operation => 'resume' ) }
sub Complete { my ( $Self, %Param ) = @_; return $Self->_Transition( %Param, Operation => 'complete' ) }
sub Cancel { my ( $Self, %Param ) = @_; return $Self->_Transition( %Param, Operation => 'cancel' ) }

sub CustomerGetByRequest {
    my ( $Self, %Param ) = @_;
    return $Self->_Error('COMMITMENT_DISABLED') if !$Self->_Enabled();
    return $Self->_Error('CUSTOMER_USER_MISSING') if !length( $Param{CustomerUserID} // q{} );
    return $Self->_Error('CUSTOMER_TENANT_MISSING') if !length( $Param{CustomerID} // q{} );
    my $RequesterID = 'customer:' . sha256_hex( $Param{CustomerUserID} );
    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');
    $DBObject->Prepare(
        SQL => 'SELECT id FROM d724_request WHERE tenant_id = ? AND id = ? AND requester_id = ?',
        Bind => [ \$Param{CustomerID}, \$Param{RequestID}, \$RequesterID ], Limit => 1,
    );
    return $Self->_Error('NOT_FOUND') if !$DBObject->FetchrowArray();
    my @Instances = $Self->_InstancesByRequest( TenantID => $Param{CustomerID}, RequestID => $Param{RequestID} );
    return $Self->_Error('NOT_FOUND') if !@Instances;
    my @Data = map { $Self->_Aggregate(%{$_}) } @Instances;
    return { Success => 1, Data => $Data[0], Objectives => \@Data };
}

sub RequestStatusSync {
    my ( $Self, %Param ) = @_;
    return $Self->_Error('REQUEST_STATUS_INVALID') if ( $Param{RequestStatus} // q{} ) !~ m{\A[a-z][a-z0-9_-]{0,29}\z}smx;
    my $Auth = $Self->_AgentAuthorize( %Param, Action => 'case.update' );
    return $Auth if !$Auth->{Success};
    my $Instance = defined $Param{CommitmentID}
        ? $Self->_InstanceRowGet( TenantID => $Param{TenantID}, CommitmentID => $Param{CommitmentID} )
        : $Self->_InstanceRowGet( TenantID => $Param{TenantID}, RequestID => $Param{RequestID} );
    return $Self->_Error('NOT_FOUND') if !$Instance;
    return $Self->_Error('VERSION_CONFLICT') if !$Self->_PositiveInteger( $Param{ExpectedVersion} ) || $Instance->{Version} != $Param{ExpectedVersion};
    my $Policy = $Self->_PolicyRowGet( TenantID => $Param{TenantID}, PolicyID => $Instance->{PolicyID} );
    return $Self->_Error('POLICY_NOT_FOUND') if !$Policy;
    my %Pause = map { $_ => 1 } @{ $Policy->{PauseStatuses} };
    if ( $Pause{ $Param{RequestStatus} } && $Instance->{Status} =~ m{\A(?:running|warning)\z}smx ) {
        return $Self->Pause(
            %Param, CommitmentID => $Instance->{CommitmentID},
            Reason => "request_status:$Param{RequestStatus}",
        );
    }
    if ( !$Pause{ $Param{RequestStatus} } && $Instance->{Status} eq 'paused' ) {
        return $Self->Resume(
            %Param, CommitmentID => $Instance->{CommitmentID},
            Reason => "request_status:$Param{RequestStatus}",
        );
    }
    return { Success => 1, Data => $Self->_Aggregate(%{$Instance}), NoChange => 1 };
}

sub SyncAllRequestStatus {
    my ( $Self, %Param ) = @_;
    my $Auth = $Self->_AgentAuthorize( %Param, Action => 'case.update' );
    return $Auth if !$Auth->{Success};
    my ( @Data, $Changed );
    for my $Instance ( $Self->_InstancesByRequest( TenantID => $Param{TenantID}, RequestID => $Param{RequestID} ) ) {
        next if $Instance->{Status} =~ m{\A(?:met|breached|cancelled)\z}smx;
        my $Result = $Self->RequestStatusSync(
            %Param, CommitmentID => $Instance->{CommitmentID}, ExpectedVersion => $Instance->{Version},
        );
        return $Result if !$Result->{Success};
        push @Data, $Result->{Data}; $Changed++ if !$Result->{NoChange};
    }
    return { Success => 1, Data => \@Data, Changed => $Changed // 0 };
}

sub Evaluate {
    my ( $Self, %Param ) = @_;
    my $Auth = $Self->_AgentAuthorize( %Param, Action => 'case.update' );
    return $Auth if !$Auth->{Success};
    return $Self->_EvaluateOne( %Param, Actor => $Auth->{Subject}->{ID} );
}

sub Sweep {
    my ( $Self, %Param ) = @_;
    return $Self->_Error('COMMITMENT_DISABLED') if !$Self->_Enabled();
    my $At = $Self->_TimeNormalize( $Param{At} );
    return $Self->_Error('TIME_INVALID') if !$At;
    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');
    $DBObject->Prepare( SQL => "SELECT id, tenant_id, version FROM d724_commitment_instance WHERE status IN ('running', 'warning') ORDER BY id", Limit => 5000 );
    my @Work;
    while ( my @Row = $DBObject->FetchrowArray() ) { push @Work, \@Row }
    my %Counts = ( Scanned => 0, Warning => 0, Breached => 0, Unchanged => 0, Errors => 0 );
    for my $Row (@Work) {
        $Counts{Scanned}++;
        my $Result = $Self->_EvaluateOne(
            CommitmentID => $Row->[0], TenantID => $Row->[1], ExpectedVersion => $Row->[2],
            At => $At, Actor => 'system:commitment-scheduler', Reason => 'scheduled_sweep',
        );
        if ( !$Result->{Success} ) { $Counts{Errors}++; next }
        if ( $Result->{Transition} eq 'warning' ) { $Counts{Warning}++ }
        elsif ( $Result->{Transition} eq 'breached' ) { $Counts{Breached}++ }
        else { $Counts{Unchanged}++ }
    }
    return { Success => $Counts{Errors} ? 0 : 1, Counts => \%Counts, At => $At };
}

sub _EvaluateOne {
    my ( $Self, %Param ) = @_;
    return $Self->_Error('VERSION_REQUIRED') if !$Self->_PositiveInteger( $Param{ExpectedVersion} );
    my $Instance = $Self->_InstanceRowGet( TenantID => $Param{TenantID}, CommitmentID => $Param{CommitmentID} );
    return $Self->_Error('NOT_FOUND') if !$Instance;
    return $Self->_Error('VERSION_CONFLICT') if $Instance->{Version} != $Param{ExpectedVersion};
    return { Success => 1, Data => $Self->_Aggregate(%{$Instance}), Transition => 'unchanged' } if $Instance->{Status} !~ m{\A(?:running|warning)\z}smx;
    my $At = $Self->_TimeNormalize( $Param{At} );
    return $Self->_Error('TIME_INVALID') if !$At;
    my $Consumed = $Self->_ConsumedAt( Instance => $Instance, At => $At );
    return $Self->_Error('CALENDAR_CALCULATION_FAILED') if !defined $Consumed;
    my $WarningAt = int( $Instance->{TargetSeconds} * $Instance->{WarningPercent} / 100 );
    my $NewStatus = $Consumed >= $Instance->{TargetSeconds} ? 'breached' : $Consumed >= $WarningAt ? 'warning' : 'running';
    return { Success => 1, Data => { %{ $Self->_Aggregate(%{$Instance}) }, CurrentConsumedSeconds => $Consumed }, Transition => 'unchanged' } if $NewStatus eq $Instance->{Status};
    my $Actor = $Param{Actor};
    my @Values = ( $NewStatus, $NewStatus eq 'breached' ? $At : undef, $Actor, $Param{TenantID}, $Param{CommitmentID}, $Param{ExpectedVersion} );
    my @Bind = map { \$_ } @Values;
    my $OK = $Kernel::OM->Get('Kernel::System::DB')->Do(
        SQL => 'UPDATE d724_commitment_instance SET status = ?, breached_at = ?, version = version + 1, change_time = current_timestamp, change_by = ? '
            . 'WHERE tenant_id = ? AND id = ? AND version = ?', Bind => \@Bind,
    );
    return $Self->_Error('DATABASE_ERROR') if !$OK;
    my $Updated = $Self->_InstanceRowGet( TenantID => $Param{TenantID}, CommitmentID => $Param{CommitmentID} );
    return $Self->_Error('VERSION_CONFLICT') if !$Updated || $Updated->{Version} != $Param{ExpectedVersion} + 1;
    my $EventType = $NewStatus eq 'breached' ? 'breached' : 'warning';
    my $EventID = $Self->_EventAdd( %{$Updated}, EventType => $EventType, EventTime => $At, FromStatus => $Instance->{Status}, ToStatus => $NewStatus, Actor => $Actor, Reason => $Param{Reason} // q{}, ConsumedSeconds => $Consumed );
    return $Self->_Error('DATABASE_ERROR') if !$EventID;
    my $Queued = $Self->_EscalationsQueue( Instance => $Updated, EventID => $EventID, Trigger => $EventType, At => $At );
    return $Queued if !$Queued->{Success};
    return { Success => 1, Data => $Self->_Aggregate(%{$Updated}), Transition => $NewStatus };
}

sub _Transition {
    my ( $Self, %Param ) = @_;
    my $Auth = $Self->_AgentAuthorize( %Param, Action => 'case.update' );
    return $Auth if !$Auth->{Success};
    return $Self->_Error('VERSION_REQUIRED') if !$Self->_PositiveInteger( $Param{ExpectedVersion} );
    return $Self->_Error('REASON_INVALID') if length( $Param{Reason} // q{} ) > 1000;
    my $Instance = $Self->_InstanceRowGet( TenantID => $Param{TenantID}, CommitmentID => $Param{CommitmentID} );
    return $Self->_Error('NOT_FOUND') if !$Instance;
    return $Self->_Error('VERSION_CONFLICT') if $Instance->{Version} != $Param{ExpectedVersion};
    my $At = $Self->_TimeNormalize( $Param{At} );
    return $Self->_Error('TIME_INVALID') if !$At;
    my ( $NewStatus, $Consumed, $RunningSince, $PausedAt, $MetAt, $BreachedAt, $Due, $Warning );
    $Consumed = $Instance->{ConsumedSeconds};
    ( $Due, $Warning ) = @{$Instance}{qw(DueTime WarningTime)};
    if ( $Param{Operation} eq 'pause' ) {
        return $Self->_Error('TRANSITION_INVALID') if $Instance->{Status} !~ m{\A(?:running|warning)\z}smx;
        $Consumed = $Self->_ConsumedAt( Instance => $Instance, At => $At );
        return $Self->_Error('CALENDAR_CALCULATION_FAILED') if !defined $Consumed;
        $NewStatus = 'paused'; $PausedAt = $At;
    }
    elsif ( $Param{Operation} eq 'resume' ) {
        return $Self->_Error('TRANSITION_INVALID') if $Instance->{Status} ne 'paused';
        my $Remaining = $Instance->{TargetSeconds} - $Consumed;
        return $Self->_Error('TRANSITION_INVALID') if $Remaining <= 0;
        $NewStatus = 'running'; $RunningSince = $At;
        $Due = $Self->_Destination( StartTime => $At, Seconds => $Remaining, CalendarID => $Instance->{CalendarID} );
        my $WarningThreshold = int( $Instance->{TargetSeconds} * $Instance->{WarningPercent} / 100 );
        $Warning = $Consumed >= $WarningThreshold ? $At : $Self->_Destination( StartTime => $At, Seconds => $WarningThreshold - $Consumed, CalendarID => $Instance->{CalendarID} );
    }
    elsif ( $Param{Operation} eq 'complete' ) {
        return $Self->_Error('TRANSITION_INVALID') if $Instance->{Status} =~ m{\A(?:met|breached|cancelled)\z}smx;
        if ( $Instance->{Status} =~ m{\A(?:running|warning)\z}smx ) {
            $Consumed = $Self->_ConsumedAt( Instance => $Instance, At => $At );
            return $Self->_Error('CALENDAR_CALCULATION_FAILED') if !defined $Consumed;
        }
        if ( $Consumed >= $Instance->{TargetSeconds} ) { $NewStatus = 'breached'; $BreachedAt = $At }
        else { $NewStatus = 'met'; $MetAt = $At }
    }
    else {
        return $Self->_Error('TRANSITION_INVALID') if $Instance->{Status} =~ m{\A(?:met|breached|cancelled)\z}smx;
        if ( $Instance->{Status} =~ m{\A(?:running|warning)\z}smx ) {
            $Consumed = $Self->_ConsumedAt( Instance => $Instance, At => $At );
            return $Self->_Error('CALENDAR_CALCULATION_FAILED') if !defined $Consumed;
        }
        $NewStatus = 'cancelled';
    }
    my $Actor = $Auth->{Subject}->{ID};
    my @Values = ( $NewStatus, $Consumed, $RunningSince, $PausedAt, $Warning, $Due, $BreachedAt, $MetAt, $Actor, $Param{TenantID}, $Param{CommitmentID}, $Param{ExpectedVersion} );
    my @Bind = map { \$_ } @Values;
    my $OK = $Kernel::OM->Get('Kernel::System::DB')->Do(
        SQL => 'UPDATE d724_commitment_instance SET status = ?, consumed_seconds = ?, running_since = ?, paused_at = ?, warning_time = ?, due_time = ?, breached_at = ?, met_at = ?, '
            . 'version = version + 1, change_time = current_timestamp, change_by = ? WHERE tenant_id = ? AND id = ? AND version = ?', Bind => \@Bind,
    );
    return $Self->_Error('DATABASE_ERROR') if !$OK;
    my $Updated = $Self->_InstanceRowGet( TenantID => $Param{TenantID}, CommitmentID => $Param{CommitmentID} );
    return $Self->_Error('VERSION_CONFLICT') if !$Updated || $Updated->{Version} != $Param{ExpectedVersion} + 1;
    my $EventType = $Param{Operation} eq 'complete' ? $NewStatus : $Param{Operation} eq 'cancel' ? 'cancelled' : $Param{Operation} . 'd';
    my $EventID = $Self->_EventAdd( %{$Updated}, EventType => $EventType, EventTime => $At, FromStatus => $Instance->{Status}, ToStatus => $NewStatus, Actor => $Actor, Reason => $Param{Reason} // q{}, ConsumedSeconds => $Consumed );
    return $Self->_Error('DATABASE_ERROR') if !$EventID;
    if ( $EventType eq 'breached' ) {
        my $Queued = $Self->_EscalationsQueue( Instance => $Updated, EventID => $EventID, Trigger => 'breached', At => $At );
        return $Queued if !$Queued->{Success};
    }
    return { Success => 1, Data => $Self->_Aggregate(%{$Updated}) };
}

sub _PolicyAuthorize {
    my ( $Self, %Param ) = @_;
    return $Self->_Error('COMMITMENT_DISABLED') if !$Self->_Enabled();
    my $Action = $Param{ReadOnly} ? 'catalog.read' : 'catalog.manage';
    my $Decision = $Kernel::OM->Get('Kernel::System::D724::TenantGuard')->DecisionGet(
        Subject => $Param{Subject}, Resource => { TenantID => $Param{TenantID} }, Action => $Action,
    );
    return $Self->_Error( 'FORBIDDEN', $Decision->{Reason} ) if !$Decision->{Allowed};
    return $Self->_Error('USER_ID_INVALID') if !$Param{ReadOnly} && !$Self->_PositiveInteger( $Param{UserID} );
    return { Success => 1 };
}

sub _AgentAuthorize {
    my ( $Self, %Param ) = @_;
    return $Self->_Error('COMMITMENT_DISABLED') if !$Self->_Enabled();
    my $Context = $Kernel::OM->Get('Kernel::System::D724::TenantDirectory')->ContextGet( UserID => $Param{UserID} );
    return $Context if !$Context->{Success};
    my $Decision = $Kernel::OM->Get('Kernel::System::D724::TenantGuard')->DecisionGet(
        Subject => $Context->{Subject}, Resource => { TenantID => $Param{TenantID} }, Action => $Param{Action},
    );
    return $Self->_Error( 'FORBIDDEN', $Decision->{Reason} ) if !$Decision->{Allowed};
    return { Success => 1, Subject => $Context->{Subject} };
}

sub _PolicyValidate {
    my ( $Self, %Param ) = @_;
    return $Self->_Error('KEY_INVALID') if ( $Param{Key} // q{} ) !~ m{\A[a-z][a-z0-9_-]{0,63}\z}smx;
    return $Self->_Error('NAME_INVALID') if !length( $Param{Name} // q{} ) || length $Param{Name} > 200;
    return $Self->_Error('CALENDAR_INVALID') if !defined $Param{CalendarID} || $Param{CalendarID} !~ m{\A[0-9]\z}smx;
    return $Self->_Error('TARGET_INVALID') if !$Self->_PositiveInteger( $Param{TargetSeconds} ) || $Param{TargetSeconds} > 31536000;
    return $Self->_Error('WARNING_INVALID') if !defined $Param{WarningPercent} || $Param{WarningPercent} !~ m{\A(?:[1-9]|[1-9][0-9])\z}smx;
    return $Self->_Error('STATUS_INVALID') if ( $Param{Status} // 'active' ) !~ m{\A(?:active|inactive)\z}smx;
    return $Self->_Error('PAUSE_STATUSES_INVALID') if ref( $Param{PauseStatuses} // [] ) ne 'ARRAY' || @{ $Param{PauseStatuses} // [] } > 20;
    my %Seen;
    for my $Status ( @{ $Param{PauseStatuses} // [] } ) {
        return $Self->_Error('PAUSE_STATUSES_INVALID') if $Status !~ m{\A[a-z][a-z0-9_-]{0,29}\z}smx || $Seen{$Status}++;
    }
    if ( exists $Param{Objectives} ) {
        return $Self->_Error('OBJECTIVES_INVALID') if ref $Param{Objectives} ne 'ARRAY' || !@{ $Param{Objectives} } || @{ $Param{Objectives} } > 10;
        my %Keys;
        for my $Objective ( @{ $Param{Objectives} } ) {
            my $Result = $Self->_ObjectiveValidate( Objective => $Objective );
            return $Result if !$Result->{Success};
            return $Self->_Error('OBJECTIVE_KEY_DUPLICATE') if $Keys{ $Objective->{key} }++;
        }
    }
    return { Success => 1 };
}

sub _ObjectiveValidate {
    my ( $Self, %Param ) = @_;
    my $Objective = $Param{Objective};
    return $Self->_Error('OBJECTIVE_INVALID') if ref $Objective ne 'HASH';
    my %Allowed = map { $_ => 1 } qw(key type target_seconds warning_percent start_signal stop_signal escalation_actions);
    return $Self->_Error('OBJECTIVE_PROPERTY_UNKNOWN') if grep { !$Allowed{$_} } keys %{$Objective};
    return $Self->_Error('OBJECTIVE_KEY_INVALID') if ( $Objective->{key} // q{} ) !~ m{\A[a-z][a-z0-9_-]{0,63}\z}smx;
    return $Self->_Error('OBJECTIVE_TYPE_INVALID') if ( $Objective->{type} // q{} ) !~ m{\A(?:response|resolution|ola)\z}smx;
    return $Self->_Error('OBJECTIVE_TARGET_INVALID') if !$Self->_PositiveInteger( $Objective->{target_seconds} ) || $Objective->{target_seconds} > 31536000;
    return $Self->_Error('OBJECTIVE_WARNING_INVALID') if !defined $Objective->{warning_percent} || $Objective->{warning_percent} !~ m{\A(?:[1-9]|[1-9][0-9])\z}smx;
    return $Self->_Error('OBJECTIVE_SIGNAL_INVALID') if ( $Objective->{start_signal} // q{} ) !~ m{\A(?:request_created|request_approved)\z}smx;
    return $Self->_Error('OBJECTIVE_SIGNAL_INVALID') if ( $Objective->{stop_signal} // q{} ) !~ m{\A(?:first_response|request_fulfilled)\z}smx;
    return $Self->_Error('OBJECTIVE_SIGNAL_INVALID') if $Objective->{start_signal} eq 'request_approved' && $Objective->{stop_signal} eq 'first_response';
    my $Actions = $Objective->{escalation_actions} // [];
    return $Self->_Error('ESCALATION_ACTIONS_INVALID') if ref $Actions ne 'ARRAY' || @{$Actions} > 20;
    my %ActionKeys;
    for my $Action ( @{$Actions} ) {
        return $Self->_Error('ESCALATION_ACTION_INVALID') if ref $Action ne 'HASH';
        my %ActionAllowed = map { $_ => 1 } qw(key trigger type target);
        return $Self->_Error('ESCALATION_ACTION_INVALID') if grep { !$ActionAllowed{$_} } keys %{$Action};
        return $Self->_Error('ESCALATION_ACTION_INVALID') if ( $Action->{key} // q{} ) !~ m{\A[a-z][a-z0-9_-]{0,63}\z}smx || $ActionKeys{ $Action->{key} }++;
        return $Self->_Error('ESCALATION_ACTION_INVALID') if ( $Action->{trigger} // q{} ) !~ m{\A(?:warning|breached)\z}smx;
        return $Self->_Error('ESCALATION_ACTION_INVALID') if ( $Action->{type} // q{} ) !~ m{\A(?:notify_role|assignment|webhook)\z}smx;
        return $Self->_Error('ESCALATION_ACTION_INVALID') if ( $Action->{target} // q{} ) !~ m{\A[a-z][a-z0-9_-]{0,63}\z}smx;
    }
    return { Success => 1 };
}

sub _LegacyObjective {
    my ( $Self, $Policy ) = @_;
    return {
        key => 'resolution', type => 'resolution', target_seconds => $Policy->{TargetSeconds},
        warning_percent => $Policy->{WarningPercent}, start_signal => 'request_created',
        stop_signal => 'request_fulfilled', escalation_actions => [],
    };
}

sub _PolicyObjectivesReplace {
    my ( $Self, %Param ) = @_;
    return { Success => 1 } if !defined $Param{Objectives};
    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');
    $DBObject->Do(
        SQL => 'DELETE FROM d724_commitment_objective WHERE tenant_id = ? AND policy_id = ?',
        Bind => [ \$Param{TenantID}, \$Param{PolicyID} ],
    ) || return $Self->_Error('DATABASE_ERROR');
    my $Sequence = 0;
    for my $Objective ( @{ $Param{Objectives} } ) {
        $Sequence++;
        my $ActionsJSON = $Kernel::OM->Get('Kernel::System::JSON')->Encode( Data => $Objective->{escalation_actions} // [], SortKeys => 1 );
        my @Values = (
            $Param{TenantID}, $Param{PolicyID}, @{$Objective}{qw(key type target_seconds warning_percent start_signal stop_signal)},
            $ActionsJSON, $Sequence,
        );
        my @Bind = map { \$_ } @Values;
        return $Self->_Error('DATABASE_ERROR') if !$DBObject->Do(
            SQL => 'INSERT INTO d724_commitment_objective (tenant_id, policy_id, key_name, objective_type, target_seconds, warning_percent, start_signal, stop_signal, escalation_actions_json, sequence_no) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
            Bind => \@Bind,
        );
    }
    return { Success => 1 };
}

sub _PolicyObjectivesGet {
    my ( $Self, %Param ) = @_;
    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');
    $DBObject->Prepare(
        SQL => 'SELECT key_name, objective_type, target_seconds, warning_percent, start_signal, stop_signal, escalation_actions_json FROM d724_commitment_objective WHERE tenant_id = ? AND policy_id = ? ORDER BY sequence_no, id',
        Bind => [ \$Param{TenantID}, \$Param{PolicyID} ],
    );
    my @Data;
    while ( my @Row = $DBObject->FetchrowArray() ) {
        my $Actions = $Kernel::OM->Get('Kernel::System::JSON')->Decode( Data => $Row[6] );
        next if ref $Actions ne 'ARRAY';
        push @Data, {
            key => $Row[0], type => $Row[1], target_seconds => $Row[2], warning_percent => $Row[3],
            start_signal => $Row[4], stop_signal => $Row[5], escalation_actions => $Actions,
        };
    }
    return \@Data;
}

sub _PolicyRowGet {
    my ( $Self, %Param ) = @_;
    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');
    my ( $Where, $Value ) = defined $Param{PolicyID} ? ( 'id', $Param{PolicyID} ) : ( 'key_name', $Param{Key} );
    $DBObject->Prepare(
        SQL => "SELECT id, tenant_id, key_name, name, calendar_id, target_seconds, warning_percent, pause_statuses_json, status, version, create_time, create_by, change_time, change_by FROM d724_commitment_policy WHERE tenant_id = ? AND $Where = ?",
        Bind => [ \$Param{TenantID}, \$Value ], Limit => 1,
    );
    my @Row = $DBObject->FetchrowArray(); return if !@Row;
    my @Keys = qw(PolicyID TenantID Key Name CalendarID TargetSeconds WarningPercent PauseStatusesJSON Status Version CreateTime CreateBy ChangeTime ChangeBy);
    my %Data; @Data{@Keys} = @Row;
    my $Pause = $Kernel::OM->Get('Kernel::System::JSON')->Decode( Data => delete $Data{PauseStatusesJSON} );
    return if ref $Pause ne 'ARRAY'; $Data{PauseStatuses} = $Pause;
    $Data{Objectives} = $Self->_PolicyObjectivesGet( TenantID => $Data{TenantID}, PolicyID => $Data{PolicyID} );
    return \%Data;
}

sub _InstanceRowGet {
    my ( $Self, %Param ) = @_;
    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');
    my ( $Where, $Value ) = defined $Param{CommitmentID} ? ( 'id', $Param{CommitmentID} ) : ( 'request_id', $Param{RequestID} );
    my $ObjectiveFilter = !defined $Param{CommitmentID} && defined $Param{ObjectiveKey} ? ' AND objective_key = ?' : q{};
    my @Values = ( $Param{TenantID}, $Value );
    push @Values, $Param{ObjectiveKey} if $ObjectiveFilter;
    my @Bind = map { \$_ } @Values;
    $DBObject->Prepare(
        SQL => "SELECT id, tenant_id, request_id, policy_id, status, objective_key, objective_type, start_signal, stop_signal, escalation_actions_json, target_seconds, consumed_seconds, calendar_id, warning_percent, start_time, running_since, paused_at, warning_time, due_time, breached_at, met_at, version, create_time, create_by, change_time, change_by FROM d724_commitment_instance WHERE tenant_id = ? AND $Where = ?$ObjectiveFilter",
        Bind => \@Bind, Limit => 1,
    );
    my @Row = $DBObject->FetchrowArray(); return if !@Row;
    my @Keys = qw(CommitmentID TenantID RequestID PolicyID Status ObjectiveKey ObjectiveType StartSignal StopSignal EscalationActionsJSON TargetSeconds ConsumedSeconds CalendarID WarningPercent StartTime RunningSince PausedAt WarningTime DueTime BreachedAt MetAt Version CreateTime CreateBy ChangeTime ChangeBy);
    my %Data; @Data{@Keys} = @Row;
    my $Actions = $Kernel::OM->Get('Kernel::System::JSON')->Decode( Data => delete $Data{EscalationActionsJSON} );
    return if ref $Actions ne 'ARRAY'; $Data{EscalationActions} = $Actions;
    return \%Data;
}

sub _InstancesByRequest {
    my ( $Self, %Param ) = @_;
    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');
    $DBObject->Prepare(
        SQL => 'SELECT id FROM d724_commitment_instance WHERE tenant_id = ? AND request_id = ? ORDER BY id',
        Bind => [ \$Param{TenantID}, \$Param{RequestID} ],
    );
    my @IDs; while ( my ($ID) = $DBObject->FetchrowArray() ) { push @IDs, $ID }
    return map { $Self->_InstanceRowGet( TenantID => $Param{TenantID}, CommitmentID => $_ ) } @IDs;
}

sub _Aggregate {
    my ( $Self, %Param ) = @_;
    my %Data = %Param;
    $Data{Policy} = $Self->_PolicyRowGet( TenantID => $Param{TenantID}, PolicyID => $Param{PolicyID} );
    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');
    $DBObject->Prepare(
        SQL => 'SELECT id, event_type, event_time, from_status, to_status, consumed_seconds, actor, reason FROM d724_commitment_event WHERE tenant_id = ? AND commitment_id = ? ORDER BY id',
        Bind => [ \$Param{TenantID}, \$Param{CommitmentID} ],
    );
    my @Events;
    while ( my @Row = $DBObject->FetchrowArray() ) {
        push @Events, { EventID => $Row[0], EventType => $Row[1], EventTime => $Row[2], FromStatus => $Row[3], ToStatus => $Row[4], ConsumedSeconds => $Row[5], Actor => $Row[6], Reason => $Row[7] };
    }
    $Data{Events} = \@Events;
    $DBObject->Prepare(
        SQL => 'SELECT id, commitment_event_id, action_key, action_type, payload_json, status, attempt_count, available_time, processed_time, last_error, delivery_ref, response_code FROM d724_escalation_outbox WHERE tenant_id = ? AND commitment_id = ? ORDER BY id',
        Bind => [ \$Param{TenantID}, \$Param{CommitmentID} ],
    );
    my @Escalations;
    while ( my @Row = $DBObject->FetchrowArray() ) {
        my $Payload = $Kernel::OM->Get('Kernel::System::JSON')->Decode( Data => $Row[4] );
        next if ref $Payload ne 'HASH';
        push @Escalations, {
            EscalationID => $Row[0], EventID => $Row[1], ActionKey => $Row[2], ActionType => $Row[3], Payload => $Payload,
            Status => $Row[5], AttemptCount => $Row[6], AvailableTime => $Row[7], ProcessedTime => $Row[8], LastError => $Row[9],
            DeliveryRef => $Row[10], ResponseCode => $Row[11],
        };
    }
    $Data{Escalations} = \@Escalations; return \%Data;
}

sub _EventAdd {
    my ( $Self, %Param ) = @_;
    my @Values = ( $Param{TenantID}, $Param{CommitmentID}, $Param{EventType}, $Param{EventTime}, $Param{FromStatus}, $Param{ToStatus}, $Param{ConsumedSeconds} // 0, $Param{Actor}, $Param{Reason} // q{} );
    my @Bind = map { \$_ } @Values;
    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');
    my $OK = $DBObject->Do(
        SQL => 'INSERT INTO d724_commitment_event (tenant_id, commitment_id, event_type, event_time, from_status, to_status, consumed_seconds, actor, reason, create_time) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, current_timestamp)', Bind => \@Bind,
    );
    return if !$OK;
    $DBObject->Prepare(
        SQL => 'SELECT id FROM d724_commitment_event WHERE tenant_id = ? AND commitment_id = ? ORDER BY id DESC',
        Bind => [ \$Param{TenantID}, \$Param{CommitmentID} ], Limit => 1,
    );
    my ($ID) = $DBObject->FetchrowArray(); return $ID;
}

sub _EscalationsQueue {
    my ( $Self, %Param ) = @_;
    my $Instance = $Param{Instance};
    my @Actions = grep { $_->{trigger} eq $Param{Trigger} } @{ $Instance->{EscalationActions} // [] };
    my $JSON = $Kernel::OM->Get('Kernel::System::JSON');
    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');
    for my $Action (@Actions) {
        my $PayloadJSON = $JSON->Encode(
            Data => {
                TenantID => $Instance->{TenantID}, RequestID => $Instance->{RequestID}, CommitmentID => $Instance->{CommitmentID},
                ObjectiveKey => $Instance->{ObjectiveKey}, ObjectiveType => $Instance->{ObjectiveType}, Trigger => $Param{Trigger},
                ActionType => $Action->{type}, Target => $Action->{target}, DueTime => $Instance->{DueTime},
            }, SortKeys => 1,
        );
        my @Values = ( $Instance->{TenantID}, $Instance->{CommitmentID}, $Param{EventID}, $Action->{key}, $Action->{type}, $PayloadJSON, 'pending', 0, $Param{At}, q{} );
        my @Bind = map { \$_ } @Values;
        my $OK = $DBObject->Do(
            SQL => 'INSERT INTO d724_escalation_outbox (tenant_id, commitment_id, commitment_event_id, action_key, action_type, payload_json, status, attempt_count, available_time, last_error, create_time, change_time) '
                . 'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, current_timestamp, current_timestamp)', Bind => \@Bind,
        );
        if (!$OK) {
            $DBObject->Prepare(
                SQL => 'SELECT id FROM d724_escalation_outbox WHERE tenant_id = ? AND commitment_event_id = ? AND action_key = ?',
                Bind => [ \$Instance->{TenantID}, \$Param{EventID}, \$Action->{key} ], Limit => 1,
            );
            return $Self->_Error('ESCALATION_QUEUE_FAILED') if !$DBObject->FetchrowArray();
        }
    }
    return { Success => 1, Queued => scalar @Actions };
}

sub _RequestExists {
    my ( $Self, %Param ) = @_;
    $Kernel::OM->Get('Kernel::System::DB')->Prepare( SQL => 'SELECT id FROM d724_request WHERE tenant_id = ? AND id = ?', Bind => [ \$Param{TenantID}, \$Param{RequestID} ], Limit => 1 );
    return $Kernel::OM->Get('Kernel::System::DB')->FetchrowArray() ? 1 : 0;
}

sub _ConsumedAt {
    my ( $Self, %Param ) = @_;
    my $Instance = $Param{Instance};
    return $Instance->{ConsumedSeconds} if !$Instance->{RunningSince};
    my $Start = $Self->_Epoch( $Instance->{RunningSince} ); my $Stop = $Self->_Epoch( $Param{At} );
    return if !defined $Start || !defined $Stop || $Stop < $Start;
    return $Instance->{ConsumedSeconds} if $Stop == $Start;
    my $DateTime = $Kernel::OM->Create( 'Kernel::System::DateTime', ObjectParams => { Epoch => $Start } );
    my $Delta = $DateTime->WorkingTime( StartTime => $Start, StopTime => $Stop, Calendar => $Instance->{CalendarID} || undef );
    return if ref $Delta ne 'HASH'; return $Instance->{ConsumedSeconds} + $Delta->{AbsoluteSeconds};
}

sub _Destination {
    my ( $Self, %Param ) = @_;
    return $Param{StartTime} if !$Param{Seconds};
    my $DateTime = $Kernel::OM->Create( 'Kernel::System::DateTime', ObjectParams => { String => $Param{StartTime}, TimeZone => 'UTC' } );
    return if !$DateTime || !$DateTime->Add( Seconds => $Param{Seconds}, AsWorkingTime => 1, Calendar => $Param{CalendarID} || undef );
    $DateTime->ToTimeZone( TimeZone => 'UTC' ); return $DateTime->ToString();
}

sub _Epoch {
    my ( $Self, $Time ) = @_;
    my $DateTime = $Kernel::OM->Create( 'Kernel::System::DateTime', ObjectParams => { String => $Time, TimeZone => 'UTC' } );
    return if !$DateTime; return $DateTime->ToEpoch();
}

sub _TimeNormalize {
    my ( $Self, $Time ) = @_;
    my $DateTime = defined $Time
        ? $Kernel::OM->Create( 'Kernel::System::DateTime', ObjectParams => { String => $Time, TimeZone => 'UTC' } )
        : $Kernel::OM->Create('Kernel::System::DateTime');
    return if !$DateTime; $DateTime->ToTimeZone( TimeZone => 'UTC' ); return $DateTime->ToString();
}

sub _Enabled { return $Kernel::OM->Get('Kernel::Config')->Get('D724::Commitment::Enabled') ? 1 : 0 }
sub _PositiveInteger { return defined $_[1] && $_[1] =~ m{\A[1-9][0-9]*\z}smx ? 1 : 0 }
sub _Error { my ( $Self, $Code, $Reason ) = @_; my $Error = { Success => 0, Error => $Code }; $Error->{Reason} = $Reason if defined $Reason; return $Error }

1;
