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

our $VERSION = '0.1.4';
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

sub Start {
    my ( $Self, %Param ) = @_;
    return $Self->_Error('COMMITMENT_DISABLED') if !$Self->_Enabled();
    return $Self->_Error('REQUEST_ID_INVALID') if !$Self->_PositiveInteger( $Param{RequestID} );
    return $Self->_Error('ACTOR_INVALID') if !defined $Param{Actor} || !length $Param{Actor} || length $Param{Actor} > 128;
    my $Policy = $Self->_PolicyRowGet( TenantID => $Param{TenantID}, Key => $Param{PolicyKey} );
    return $Self->_Error('POLICY_NOT_FOUND') if !$Policy || $Policy->{Status} ne 'active';
    return $Self->_Error('REQUEST_NOT_FOUND') if !$Self->_RequestExists( TenantID => $Param{TenantID}, RequestID => $Param{RequestID} );
    my $Existing = $Self->_InstanceRowGet( TenantID => $Param{TenantID}, RequestID => $Param{RequestID} );
    return { Success => 1, Data => $Self->_Aggregate( %{$Existing} ), IdempotentReplay => 1 } if $Existing && $Existing->{PolicyID} == $Policy->{PolicyID};
    return $Self->_Error('REQUEST_COMMITMENT_EXISTS') if $Existing;
    my $Start = $Self->_TimeNormalize( $Param{StartTime} );
    return $Self->_Error('TIME_INVALID') if !$Start;
    my $Due = $Self->_Destination( StartTime => $Start, Seconds => $Policy->{TargetSeconds}, CalendarID => $Policy->{CalendarID} );
    my $WarningSeconds = int( $Policy->{TargetSeconds} * $Policy->{WarningPercent} / 100 );
    my $Warning = $Self->_Destination( StartTime => $Start, Seconds => $WarningSeconds, CalendarID => $Policy->{CalendarID} );
    return $Self->_Error('CALENDAR_CALCULATION_FAILED') if !$Due || !$Warning;
    my %Pause = map { $_ => 1 } @{ $Policy->{PauseStatuses} };
    my $InitialStatus = $Pause{ $Param{RequestStatus} // q{} } ? 'paused' : 'running';
    my $RunningSince = $InitialStatus eq 'running' ? $Start : undef;
    my $PausedAt     = $InitialStatus eq 'paused'  ? $Start : undef;
    my @Values = (
        $Param{TenantID}, $Param{RequestID}, $Policy->{PolicyID}, $InitialStatus, $Policy->{TargetSeconds}, 0,
        $Policy->{CalendarID}, $Policy->{WarningPercent}, $Start, $RunningSince, $PausedAt, $Warning, $Due, $Param{Actor}, $Param{Actor},
    );
    my @Bind = map { \$_ } @Values;
    my $OK = $Kernel::OM->Get('Kernel::System::DB')->Do(
        SQL => 'INSERT INTO d724_commitment_instance (tenant_id, request_id, policy_id, status, target_seconds, consumed_seconds, calendar_id, warning_percent, '
            . 'start_time, running_since, paused_at, warning_time, due_time, version, create_time, create_by, change_time, change_by) '
            . 'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1, current_timestamp, ?, current_timestamp, ?)', Bind => \@Bind,
    );
    return $Self->_Error('DATABASE_ERROR') if !$OK;
    my $Instance = $Self->_InstanceRowGet( TenantID => $Param{TenantID}, RequestID => $Param{RequestID} );
    return $Self->_Error('DATABASE_ERROR') if !$Instance;
    $Self->_EventAdd( %{$Instance}, EventType => 'started', EventTime => $Start, FromStatus => q{}, ToStatus => $InitialStatus, Actor => $Param{Actor}, Reason => $InitialStatus eq 'paused' ? 'initial_request_status:' . $Param{RequestStatus} : q{} );
    return { Success => 1, Data => $Self->_Aggregate(%{$Instance}), IdempotentReplay => 0 };
}

sub AgentGetByRequest {
    my ( $Self, %Param ) = @_;
    my $Auth = $Self->_AgentAuthorize( %Param, Action => 'case.read' );
    return $Auth if !$Auth->{Success};
    my $Instance = $Self->_InstanceRowGet( TenantID => $Param{TenantID}, RequestID => $Param{RequestID} );
    return $Self->_Error('NOT_FOUND') if !$Instance;
    return { Success => 1, Data => $Self->_Aggregate(%{$Instance}) };
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
    my $Instance = $Self->_InstanceRowGet( TenantID => $Param{CustomerID}, RequestID => $Param{RequestID} );
    return $Self->_Error('NOT_FOUND') if !$Instance;
    return { Success => 1, Data => $Self->_Aggregate(%{$Instance}) };
}

sub RequestStatusSync {
    my ( $Self, %Param ) = @_;
    return $Self->_Error('REQUEST_STATUS_INVALID') if ( $Param{RequestStatus} // q{} ) !~ m{\A[a-z][a-z0-9_-]{0,29}\z}smx;
    my $Auth = $Self->_AgentAuthorize( %Param, Action => 'case.update' );
    return $Auth if !$Auth->{Success};
    my $Instance = $Self->_InstanceRowGet( TenantID => $Param{TenantID}, RequestID => $Param{RequestID} );
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
    $Self->_EventAdd( %{$Updated}, EventType => $NewStatus eq 'breached' ? 'breached' : 'warning', EventTime => $At, FromStatus => $Instance->{Status}, ToStatus => $NewStatus, Actor => $Actor, Reason => $Param{Reason} // q{}, ConsumedSeconds => $Consumed );
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
    $Self->_EventAdd( %{$Updated}, EventType => $EventType, EventTime => $At, FromStatus => $Instance->{Status}, ToStatus => $NewStatus, Actor => $Actor, Reason => $Param{Reason} // q{}, ConsumedSeconds => $Consumed );
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
    return { Success => 1 };
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
    return \%Data;
}

sub _InstanceRowGet {
    my ( $Self, %Param ) = @_;
    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');
    my ( $Where, $Value ) = defined $Param{CommitmentID} ? ( 'id', $Param{CommitmentID} ) : ( 'request_id', $Param{RequestID} );
    $DBObject->Prepare(
        SQL => "SELECT id, tenant_id, request_id, policy_id, status, target_seconds, consumed_seconds, calendar_id, warning_percent, start_time, running_since, paused_at, warning_time, due_time, breached_at, met_at, version, create_time, create_by, change_time, change_by FROM d724_commitment_instance WHERE tenant_id = ? AND $Where = ?",
        Bind => [ \$Param{TenantID}, \$Value ], Limit => 1,
    );
    my @Row = $DBObject->FetchrowArray(); return if !@Row;
    my @Keys = qw(CommitmentID TenantID RequestID PolicyID Status TargetSeconds ConsumedSeconds CalendarID WarningPercent StartTime RunningSince PausedAt WarningTime DueTime BreachedAt MetAt Version CreateTime CreateBy ChangeTime ChangeBy);
    my %Data; @Data{@Keys} = @Row; return \%Data;
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
    $Data{Events} = \@Events; return \%Data;
}

sub _EventAdd {
    my ( $Self, %Param ) = @_;
    my @Values = ( $Param{TenantID}, $Param{CommitmentID}, $Param{EventType}, $Param{EventTime}, $Param{FromStatus}, $Param{ToStatus}, $Param{ConsumedSeconds} // 0, $Param{Actor}, $Param{Reason} // q{} );
    my @Bind = map { \$_ } @Values;
    return $Kernel::OM->Get('Kernel::System::DB')->Do(
        SQL => 'INSERT INTO d724_commitment_event (tenant_id, commitment_id, event_type, event_time, from_status, to_status, consumed_seconds, actor, reason, create_time) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, current_timestamp)', Bind => \@Bind,
    );
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
