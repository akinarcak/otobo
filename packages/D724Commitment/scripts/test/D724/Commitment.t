# --
# D724 ESM is an enterprise service management platform based on OTOBO.
# Copyright (C) 2026 Data Market Bilgi Hizmetleri A.S.
# SPDX-License-Identifier: GPL-3.0-only
# --

use v5.24;
use strict;
use warnings;
use utf8;
use Digest::SHA qw(hmac_sha256_hex);
use Test2::V0;
use Kernel::System::UnitTest::RegisterOM;
use Kernel::System::Email ();
use Kernel::System::WebUserAgent ();

$Kernel::OM->ObjectParamAdd( 'Kernel::System::UnitTest::Helper' => { RestoreDatabase => 1 } );
my $Helper = $Kernel::OM->Get('Kernel::System::UnitTest::Helper');
$Helper->ConfigSettingChange( Key => 'D724::Catalog::Enabled', Value => 1 );
$Helper->ConfigSettingChange( Key => 'D724::Request::Enabled', Value => 1 );
$Helper->ConfigSettingChange( Key => 'D724::Commitment::Enabled', Value => 1 );
$Helper->ConfigSettingChange( Key => 'D724::Commitment::EscalationDispatchEnabled', Value => 1 );
$Helper->ConfigSettingChange( Key => 'D724::Commitment::EscalationBatchSize', Value => 25 );
$Helper->ConfigSettingChange( Key => 'D724::Commitment::EscalationMaxAttempts', Value => 3 );
$Helper->ConfigSettingChange( Key => 'CheckEmailAddresses', Value => 0 );
$Helper->ConfigSettingChange( Key => 'OTOBOTimeZone', Value => 'UTC' );
$Helper->ConfigSettingChange(
    Key => 'TimeWorkingHours',
    Value => { Mon => [ 8 .. 16 ], Tue => [ 8 .. 16 ], Wed => [ 8 .. 16 ], Thu => [ 8 .. 16 ], Fri => [ 8 .. 16 ], Sat => [], Sun => [] },
);
$Helper->ConfigSettingChange( Key => 'TimeVacationDays', Value => {} );
$Helper->ConfigSettingChange( Key => 'TimeVacationDaysOneTime', Value => {} );

my $Suffix = lc $Helper->GetRandomID();
my $TenantA = "commit-a-$Suffix";
my $TenantB = "commit-b-$Suffix";
my $UserObject = $Kernel::OM->Get('Kernel::System::User');
my $AdminID = $UserObject->UserAdd(
    UserFirstname => 'Commitment', UserLastname => 'Admin', UserLogin => "commit-admin-$Suffix",
    UserEmail => "commit-admin-$Suffix\@example.test", ValidID => 1, ChangeUserID => 1,
) || die 'Could not create commitment admin';
my $OtherID = $UserObject->UserAdd(
    UserFirstname => 'Commitment', UserLastname => 'Other', UserLogin => "commit-other-$Suffix",
    UserEmail => "commit-other-$Suffix\@example.test", ValidID => 1, ChangeUserID => 1,
) || die 'Could not create commitment other user';

my $DBObject = $Kernel::OM->Get('Kernel::System::DB');
my $Dispatcher = $Kernel::OM->Get('Kernel::System::D724::EscalationDispatcher');
for my $Tenant ( $TenantA, $TenantB ) {
    my @Values = ( $Tenant, "Tenant $Tenant", 'active', 1, $AdminID, $AdminID ); my @Bind = map { \$_ } @Values;
    $DBObject->Do(
        SQL => 'INSERT INTO d724_tenant (key_name, name, status, version, create_time, create_by, change_time, change_by) VALUES (?, ?, ?, ?, current_timestamp, ?, current_timestamp, ?)', Bind => \@Bind,
    ) || die 'Could not create tenant';
}
for my $Role ( [ $TenantA, $AdminID, 'tenant_admin' ], [ $TenantA, $AdminID, 'service_owner' ], [ $TenantB, $OtherID, 'agent' ] ) {
    my @Values = ( @{$Role}, 'active', $AdminID, $AdminID ); my @Bind = map { \$_ } @Values;
    $DBObject->Do(
        SQL => 'INSERT INTO d724_tenant_agent_role (tenant_id, user_id, role_name, status, create_time, create_by, change_time, change_by) VALUES (?, ?, ?, ?, current_timestamp, ?, current_timestamp, ?)', Bind => \@Bind,
    ) || die 'Could not create membership';
}

my $Subject = { ID => "agent:$AdminID", TenantIDs => [$TenantA], RoleBindings => { $TenantA => ['tenant_admin'] } };
my $OtherSubject = { ID => "agent:$OtherID", TenantIDs => [$TenantB], RoleBindings => { $TenantB => ['agent'] } };
my $Commitment = $Kernel::OM->Get('Kernel::System::D724::Commitment');
my $Policy = $Commitment->PolicyCreate(
    Subject => $Subject, UserID => $AdminID, TenantID => $TenantA,
    Key => 'standard-resolution', Name => 'Standard resolution', CalendarID => 0,
    TargetSeconds => 14_400, WarningPercent => 50, PauseStatuses => ['waiting_customer'], Status => 'active',
);
ok( $Policy->{Success}, 'tenant admin creates commitment policy' );
is( $Policy->{Data}->{PauseStatuses}, ['waiting_customer'], 'pause rules are persisted' );
is(
    $Commitment->PolicyCreate(
        Subject => $Subject, UserID => $AdminID, TenantID => $TenantA,
        Key => 'bad-warning', Name => 'Bad', CalendarID => 0, TargetSeconds => 3600, WarningPercent => 100,
    )->{Error},
    'WARNING_INVALID', 'warning threshold must occur before breach',
);
is(
    $Commitment->PolicyGet( Subject => $OtherSubject, TenantID => $TenantA, PolicyID => $Policy->{Data}->{PolicyID} )->{Error},
    'FORBIDDEN', 'policy cannot be read across tenant boundary',
);

my $Catalog = $Kernel::OM->Get('Kernel::System::D724::Catalog');
my %CatalogCall = ( Subject => $Subject, TenantID => $TenantA, UserID => $AdminID );
my $Service = $Catalog->ServiceCreate( %CatalogCall, Key => 'it', Name => 'IT', Status => 'active' );
my $Offering = $Catalog->OfferingCreate( %CatalogCall, ServiceID => $Service->{Data}->{ServiceID}, Key => 'support', Name => 'Support', Status => 'active' );
my $Item = $Catalog->CatalogItemCreate( %CatalogCall, OfferingID => $Offering->{Data}->{OfferingID}, Key => 'help', Name => 'Help', Status => 'active' );
$Catalog->CatalogItemSchemaSet( %CatalogCall, CatalogItemID => $Item->{Data}->{CatalogItemID}, Schema => { version => 1, fields => [] } );
my $RequestObject = $Kernel::OM->Get('Kernel::System::D724::Request');
my $NewRequest = sub {
    my ($Key) = @_;
    return $RequestObject->CustomerSubmit(
        CustomerUserID => "customer-$Suffix\@example.test", CustomerID => $TenantA,
        CatalogItemID => $Item->{Data}->{CatalogItemID}, IdempotencyKey => "commit-$Suffix-$Key-0001", Answers => {},
    )->{Data};
};
my $Request = $NewRequest->('met');
my $Started = $Commitment->Start(
    TenantID => $TenantA, RequestID => $Request->{RequestID}, PolicyKey => 'standard-resolution',
    Actor => $Request->{RequesterID}, StartTime => '2026-07-27 09:00:00',
);
ok( $Started->{Success}, 'commitment starts for tenant request' );
is( $Started->{Data}->{DueTime}, '2026-07-27 13:00:00', 'due time uses four business hours' );
is( $Started->{Data}->{WarningTime}, '2026-07-27 11:00:00', 'warning time uses policy threshold' );
is(
    $Commitment->Start(
        TenantID => $TenantA, RequestID => $Request->{RequestID}, PolicyKey => 'standard-resolution',
        Actor => $Request->{RequesterID}, StartTime => '2026-07-27 09:00:00',
    )->{IdempotentReplay},
    1, 'start is idempotent for request and policy',
);

my $UpdatedPolicy = $Commitment->PolicyUpdate(
    Subject => $Subject, UserID => $AdminID, TenantID => $TenantA, PolicyID => $Policy->{Data}->{PolicyID},
    ExpectedVersion => 1, TargetSeconds => 28_800,
);
is( $UpdatedPolicy->{Data}->{TargetSeconds}, 28_800, 'policy can evolve for future requests' );
is(
    $Commitment->AgentGetByRequest( UserID => $AdminID, TenantID => $TenantA, RequestID => $Request->{RequestID} )->{Data}->{TargetSeconds},
    14_400, 'running commitment retains immutable policy snapshot',
);

my $Paused = $Commitment->RequestStatusSync(
    UserID => $AdminID, TenantID => $TenantA, RequestID => $Request->{RequestID},
    ExpectedVersion => $Started->{Data}->{Version}, RequestStatus => 'waiting_customer', At => '2026-07-27 11:00:00',
);
is( $Paused->{Data}->{Status}, 'paused', 'configured request status pauses commitment' );
is( $Paused->{Data}->{ConsumedSeconds}, 7200, 'pause stores consumed business seconds' );
my $NoChange = $Commitment->RequestStatusSync(
    UserID => $AdminID, TenantID => $TenantA, RequestID => $Request->{RequestID},
    ExpectedVersion => $Paused->{Data}->{Version}, RequestStatus => 'waiting_customer', At => '2026-07-27 12:00:00',
);
ok( $NoChange->{NoChange}, 'repeated paused request status is idempotent' );
my $Resumed = $Commitment->RequestStatusSync(
    UserID => $AdminID, TenantID => $TenantA, RequestID => $Request->{RequestID},
    ExpectedVersion => $Paused->{Data}->{Version}, RequestStatus => 'in_fulfillment', At => '2026-07-28 09:00:00',
);
is( $Resumed->{Data}->{Status}, 'running', 'leaving configured status resumes commitment' );
is( $Resumed->{Data}->{DueTime}, '2026-07-28 11:00:00', 'pause shifts due time by remaining business time' );
my $Warning = $Commitment->Evaluate(
    UserID => $AdminID, TenantID => $TenantA, CommitmentID => $Resumed->{Data}->{CommitmentID},
    ExpectedVersion => $Resumed->{Data}->{Version}, At => '2026-07-28 09:01:00', Reason => 'scheduler',
);
is( $Warning->{Data}->{Status}, 'warning', 'elapsed warning threshold creates warning state' );
is(
    $Commitment->Evaluate(
        UserID => $AdminID, TenantID => $TenantA, CommitmentID => $Resumed->{Data}->{CommitmentID},
        ExpectedVersion => $Resumed->{Data}->{Version}, At => '2026-07-28 09:02:00',
    )->{Error},
    'VERSION_CONFLICT', 'stale scheduler evaluation cannot overwrite state',
);
my $Met = $Commitment->Complete(
    UserID => $AdminID, TenantID => $TenantA, CommitmentID => $Warning->{Data}->{CommitmentID},
    ExpectedVersion => $Warning->{Data}->{Version}, At => '2026-07-28 10:00:00', Reason => 'request_fulfilled',
);
is( $Met->{Data}->{Status}, 'met', 'completion before target records met commitment' );
is( [ map { $_->{EventType} } @{ $Met->{Data}->{Events} } ], [qw(started paused resumed warning met)], 'append-only evidence preserves lifecycle' );

my $BreachRequest = $NewRequest->('breach');
my $BreachStart = $Commitment->Start(
    TenantID => $TenantA, RequestID => $BreachRequest->{RequestID}, PolicyKey => 'standard-resolution',
    Actor => $BreachRequest->{RequesterID}, StartTime => '2026-07-27 09:00:00',
);
is( $BreachStart->{Data}->{TargetSeconds}, 28_800, 'new request receives updated policy snapshot' );
my $Breached = $Commitment->Evaluate(
    UserID => $AdminID, TenantID => $TenantA, CommitmentID => $BreachStart->{Data}->{CommitmentID},
    ExpectedVersion => $BreachStart->{Data}->{Version}, At => '2026-07-27 17:00:00', Reason => 'scheduler',
);
is( $Breached->{Data}->{Status}, 'breached', 'target business time crossing records breach' );
is( $Breached->{Data}->{BreachedAt}, '2026-07-27 17:00:00', 'breach evidence records evaluation time' );
my $SweepRequest = $NewRequest->('sweep');
my $SweepStart = $Commitment->Start(
    TenantID => $TenantA, RequestID => $SweepRequest->{RequestID}, PolicyKey => 'standard-resolution',
    Actor => $SweepRequest->{RequesterID}, StartTime => '2026-07-27 09:00:00',
);
ok( $SweepStart->{Success}, 'scheduler fixture commitment starts' );
my $Sweep = $Commitment->Sweep( At => '2026-07-27 17:00:00' );
ok( $Sweep->{Success}, 'scheduled sweep evaluates active commitments' );
ok( $Sweep->{Counts}->{Breached} >= 1, 'scheduled sweep emits breach transition' );
my $AfterSweep = $Commitment->AgentGetByRequest( UserID => $AdminID, TenantID => $TenantA, RequestID => $SweepRequest->{RequestID} );
is( $AfterSweep->{Data}->{Status}, 'breached', 'scheduler persists breached state' );
is( $AfterSweep->{Data}->{Events}->[-1]->{Actor}, 'automation:commitment-sweep', 'scheduler transition records tenant-bound automation actor' );

my $MultiPolicy = $Commitment->PolicyCreate(
    Subject => $Subject, UserID => $AdminID, TenantID => $TenantA,
    Key => 'premium-multi', Name => 'Premium multi-objective', CalendarID => 0,
    TargetSeconds => 14_400, WarningPercent => 75, PauseStatuses => ['awaiting_approval'], Status => 'active',
    Objectives => [
        {
            key => 'first-response', type => 'response', target_seconds => 3600, warning_percent => 50,
            start_signal => 'request_created', stop_signal => 'first_response',
            escalation_actions => [ { key => 'warn-owner', trigger => 'warning', type => 'notify_role', target => 'service_owner' } ],
        },
        {
            key => 'resolution', type => 'resolution', target_seconds => 14_400, warning_percent => 75,
            start_signal => 'request_created', stop_signal => 'request_fulfilled',
            escalation_actions => [ { key => 'assign-breach', trigger => 'breached', type => 'assignment', target => 'resolver-escalation' } ],
        },
        {
            key => 'internal-ola', type => 'ola', target_seconds => 7200, warning_percent => 75,
            start_signal => 'request_approved', stop_signal => 'request_fulfilled', escalation_actions => [],
        },
    ],
);
ok( $MultiPolicy->{Success}, 'multi-objective response, resolution and OLA policy is created' );
is( [ map { $_->{type} } @{ $MultiPolicy->{Data}->{Objectives} } ], [qw(response resolution ola)], 'objective order and types are persisted' );
my $MultiRequest = $NewRequest->('multi');
my $MultiStarted = $Commitment->StartAll(
    TenantID => $TenantA, RequestID => $MultiRequest->{RequestID}, PolicyKey => 'premium-multi',
    Actor => $MultiRequest->{RequesterID}, StartTime => '2026-07-27 09:00:00', Signal => 'request_created', RequestStatus => 'in_fulfillment',
);
is( scalar @{ $MultiStarted->{Data} }, 2, 'request-created starts response and resolution objectives only' );
my $MultiSweep = $Commitment->Sweep( At => '2026-07-27 09:31:00' );
ok( $MultiSweep->{Success}, 'multi-objective sweep succeeds' );
my $MultiList = $Commitment->AgentListByRequest( UserID => $AdminID, TenantID => $TenantA, RequestID => $MultiRequest->{RequestID} );
my ($ResponseObjective) = grep { $_->{ObjectiveType} eq 'response' } @{ $MultiList->{Data} };
is( $ResponseObjective->{Status}, 'warning', 'response objective reaches warning independently' );
is( $ResponseObjective->{Escalations}->[0]->{ActionType}, 'notify_role', 'warning queues configured escalation action' );
is( $ResponseObjective->{Escalations}->[0]->{Payload}->{Target}, 'service_owner', 'outbox payload preserves safe target' );
$Commitment->Sweep( At => '2026-07-27 09:32:00' );
$MultiList = $Commitment->AgentListByRequest( UserID => $AdminID, TenantID => $TenantA, RequestID => $MultiRequest->{RequestID} );
($ResponseObjective) = grep { $_->{ObjectiveType} eq 'response' } @{ $MultiList->{Data} };
is( scalar @{ $ResponseObjective->{Escalations} }, 1, 'repeated sweep does not duplicate escalation action' );
my $FailedDispatch = $Dispatcher->Dispatch(
    At => '2026-07-27 09:33:00', WorkerID => 'test-worker-a',
    Handlers => { notify_role => sub { return { Success => 0, Error => 'TEST_TRANSIENT_FAILURE' } } },
);
is( $FailedDispatch->{Counts}->{Retried}, 1, 'transient delivery failure schedules retry' );
$MultiList = $Commitment->AgentListByRequest( UserID => $AdminID, TenantID => $TenantA, RequestID => $MultiRequest->{RequestID} );
($ResponseObjective) = grep { $_->{ObjectiveType} eq 'response' } @{ $MultiList->{Data} };
is( $ResponseObjective->{Escalations}->[0]->{Status}, 'retry', 'retry state is visible in commitment evidence' );
is( $ResponseObjective->{Escalations}->[0]->{AttemptCount}, 1, 'failed attempt is counted once' );
my $NestedClaimed;
my $SuccessfulDispatch = $Dispatcher->Dispatch(
    At => '2026-07-27 09:35:00', WorkerID => 'test-worker-b',
    Handlers => { notify_role => sub {
        $NestedClaimed = $Dispatcher->Dispatch(
            At => '2026-07-27 09:35:00', WorkerID => 'test-worker-racing',
            Handlers => { notify_role => sub { die 'leased action must not reach racing worker' } },
        )->{Counts}->{Claimed};
        return { Success => 1, DeliveryRef => 'test:notification:1', ResponseCode => 'QUEUED' };
    } },
);
is( $SuccessfulDispatch->{Counts}->{Delivered}, 1, 'retry is delivered by a later dispatcher run' );
is( $NestedClaimed, 0, 'active lease prevents a racing worker from claiming the same action' );
$MultiList = $Commitment->AgentListByRequest( UserID => $AdminID, TenantID => $TenantA, RequestID => $MultiRequest->{RequestID} );
($ResponseObjective) = grep { $_->{ObjectiveType} eq 'response' } @{ $MultiList->{Data} };
is( $ResponseObjective->{Escalations}->[0]->{Status}, 'delivered', 'delivery evidence becomes terminal' );
is( $ResponseObjective->{Escalations}->[0]->{DeliveryRef}, 'test:notification:1', 'delivery reference is retained for audit' );
is( $Dispatcher->Dispatch( At => '2026-07-27 09:36:00', WorkerID => 'test-worker-c', Handlers => {} )->{Counts}->{Claimed}, 0, 'delivered action is never claimed again' );
my $EscalationID = $ResponseObjective->{Escalations}->[0]->{EscalationID};
my ( $Retry, $Attempt, $Available, $Empty ) = ( 'retry', 2, '2026-07-27 09:37:00', q{} );
$DBObject->Do(
    SQL => 'UPDATE d724_escalation_outbox SET status = ?, attempt_count = ?, available_time = ?, processed_time = NULL, delivery_ref = ?, response_code = ? WHERE id = ?',
    Bind => [ \$Retry, \$Attempt, \$Available, \$Empty, \$Empty, \$EscalationID ],
);
my $DeadDispatch = $Dispatcher->Dispatch(
    At => '2026-07-27 09:37:00', WorkerID => 'test-worker-dead',
    Handlers => { notify_role => sub { return { Success => 0, Error => 'TEST_PERMANENT_FAILURE' } } },
);
is( $DeadDispatch->{Counts}->{Dead}, 1, 'maximum attempt moves action to dead-letter state' );
$MultiList = $Commitment->AgentListByRequest( UserID => $AdminID, TenantID => $TenantA, RequestID => $MultiRequest->{RequestID} );
($ResponseObjective) = grep { $_->{ObjectiveType} eq 'response' } @{ $MultiList->{Data} };
is( $ResponseObjective->{Escalations}->[0]->{Status}, 'dead', 'dead-letter state remains visible in audit evidence' );
is(
    $Dispatcher->Replay(
        Subject => $OtherSubject, TenantID => $TenantA, OutboxID => $EscalationID,
        ExpectedAttemptCount => 3, At => '2026-07-27 09:38:00',
    )->{Error},
    'FORBIDDEN', 'another tenant cannot replay a dead-letter delivery',
);
is(
    $Dispatcher->Replay(
        Subject => $Subject, TenantID => $TenantA, OutboxID => $EscalationID,
        ExpectedAttemptCount => 2, At => '2026-07-27 09:38:00',
    )->{Error},
    'VERSION_CONFLICT', 'dead-letter replay uses the attempt count as an optimistic lock',
);
my $Replayed = $Dispatcher->Replay(
    Subject => $Subject, TenantID => $TenantA, OutboxID => $EscalationID,
    ExpectedAttemptCount => 3, At => '2026-07-27 09:38:00',
);
ok( $Replayed->{Success}, 'tenant administrator requeues a dead-letter delivery' );
is( $Replayed->{Data}->{ReplayCount}, 1, 'dead-letter replay count advances without losing history' );
is(
    $Dispatcher->Replay(
        Subject => $Subject, TenantID => $TenantA, OutboxID => $EscalationID,
        ExpectedAttemptCount => 3, At => '2026-07-27 09:38:00',
    )->{Error},
    'REPLAY_STATE_INVALID', 'a non-dead delivery cannot be replayed again',
);
my $ReplayDispatch = $Dispatcher->Dispatch(
    At => '2026-07-27 09:38:00', WorkerID => 'test-worker-replay',
    Handlers => { notify_role => sub { return { Success => 1, DeliveryRef => 'test:replay:1', ResponseCode => 'QUEUED' } } },
);
is( $ReplayDispatch->{Counts}->{Delivered}, 1, 'requeued delivery returns through the normal leased dispatcher' );
$MultiList = $Commitment->AgentListByRequest( UserID => $AdminID, TenantID => $TenantA, RequestID => $MultiRequest->{RequestID} );
($ResponseObjective) = grep { $_->{ObjectiveType} eq 'response' } @{ $MultiList->{Data} };
is( $ResponseObjective->{Escalations}->[0]->{Status}, 'delivered', 'replayed delivery reaches a terminal delivered state' );
is( $ResponseObjective->{Escalations}->[0]->{ReplayCount}, 1, 'commitment evidence exposes replay count' );
is( $ResponseObjective->{Escalations}->[0]->{AttemptCount}, 1, 'current replay-cycle attempt count restarts from zero' );
ok( $ResponseObjective->{Escalations}->[0]->{LifetimeAttemptCount} >= 3, 'lifetime attempts remain monotonic across replay' );
my $ResponseSignal = $Commitment->Signal(
    UserID => $AdminID, TenantID => $TenantA, RequestID => $MultiRequest->{RequestID}, PolicyKey => 'premium-multi',
    Signal => 'first_response', RequestStatus => 'in_fulfillment', At => '2026-07-27 09:45:00',
);
is( $ResponseSignal->{Data}->{Stopped}->[0]->{Status}, 'met', 'first response signal completes response objective' );
my $ApprovalSignal = $Commitment->Signal(
    UserID => $AdminID, TenantID => $TenantA, RequestID => $MultiRequest->{RequestID}, PolicyKey => 'premium-multi',
    Signal => 'request_approved', RequestStatus => 'in_fulfillment', At => '2026-07-27 10:00:00',
);
is( $ApprovalSignal->{Data}->{Started}->[0]->{ObjectiveType}, 'ola', 'approval signal starts internal OLA objective' );
my $FulfilledSignal = $Commitment->Signal(
    UserID => $AdminID, TenantID => $TenantA, RequestID => $MultiRequest->{RequestID}, PolicyKey => 'premium-multi',
    Signal => 'request_fulfilled', RequestStatus => 'fulfilled', At => '2026-07-27 11:00:00',
);
is( [ sort map { $_->{ObjectiveType} } @{ $FulfilledSignal->{Data}->{Stopped} } ], [qw(ola resolution)], 'fulfillment closes remaining resolution and OLA objectives' );
is(
    $Commitment->AgentGetByRequest( UserID => $OtherID, TenantID => $TenantA, RequestID => $Request->{RequestID} )->{Error},
    'FORBIDDEN', 'agent cannot read another tenant commitment',
);

my $IntegratedSchema = $Catalog->CatalogItemSchemaSet(
    %CatalogCall, CatalogItemID => $Item->{Data}->{CatalogItemID}, ExpectedVersion => 1,
    Schema => {
        version => 2, fields => [],
        workflow => {
            commitment => { policy_key => 'standard-resolution' },
            fulfillment => [ { key => 'fulfill', name => 'Fulfill request', type => 'manual' } ],
        },
    },
);
ok( $IntegratedSchema->{Success}, 'catalog workflow references tenant-local commitment policy' );
my $Integrated = $RequestObject->CustomerSubmit(
    CustomerUserID => "customer-$Suffix\@example.test", CustomerID => $TenantA,
    CatalogItemID => $Item->{Data}->{CatalogItemID}, IdempotencyKey => "commit-$Suffix-integrated-0001", Answers => {},
);
ok( $Integrated->{Success}, 'request submission automatically starts commitment' );
my $CustomerIntegrated = $RequestObject->CustomerGet(
    CustomerUserID => "customer-$Suffix\@example.test", CustomerID => $TenantA, RequestID => $Integrated->{Data}->{RequestID},
);
is( $CustomerIntegrated->{Data}->{Commitment}->{Status}, 'running', 'customer request view includes its commitment' );
my ($AgentIntegrated) = grep { $_->{RequestID} == $Integrated->{Data}->{RequestID} } @{
    $RequestObject->AgentList( UserID => $AdminID, TenantID => $TenantA )->{Data}
};
is( $AgentIntegrated->{Commitment}->{Policy}->{Key}, 'standard-resolution', 'agent list includes policy and due data' );
my $IntegratedTask = $Integrated->{Data}->{Tasks}->[0];
my %EmailCall;
{
    no warnings 'redefine';
    local *Kernel::System::Email::Send = sub { my ( $Self, %Param ) = @_; %EmailCall = %Param; return 1 };
    my $Notification = $Dispatcher->_NotifyRole( {
        ID => 9000, TenantID => $TenantA,
        Payload => { RequestID => $Integrated->{Data}->{RequestID}, Target => 'service_owner', Trigger => 'warning', ObjectiveKey => 'resolution', DueTime => '2026-07-27 17:00:00' },
    } );
    ok( $Notification->{Success}, 'role notification adapter queues email through OTOBO transport' );
}
like( $EmailCall{To}, qr{\Qcommit-admin-$Suffix\E\@example\.test}, 'role notification resolves recipients only from tenant membership' );
is( $EmailCall{CustomHeaders}->{'X-D724-Tenant'}, $TenantA, 'notification carries tenant audit header' );
my $Assignment = $Dispatcher->_Assign( {
    ID => 9001, TenantID => $TenantA,
    Payload => { RequestID => $Integrated->{Data}->{RequestID}, Target => 'resolver-escalation' },
} );
ok( $Assignment->{Success}, 'assignment adapter assigns active fulfillment work' );
my ($AssignedRequest) = grep { $_->{RequestID} == $Integrated->{Data}->{RequestID} } @{
    $RequestObject->AgentList( UserID => $AdminID, TenantID => $TenantA )->{Data}
};
is( $AssignedRequest->{Tasks}->[0]->{AssignedGroup}, 'resolver-escalation', 'assignment is tenant-scoped and visible to agents' );
$IntegratedTask = $AssignedRequest->{Tasks}->[0];

$Helper->ConfigSettingChange( Key => 'D724::Commitment::WebhookAllowedHosts', Value => ['hooks.example.test'] );
$Helper->ConfigSettingChange(
    Key => 'D724::Commitment::WebhookEndpoints',
    Value => { 'audit-hook::URL' => 'https://hooks.example.test/d724', 'audit-hook::Secret' => '0123456789abcdef0123456789abcdef' },
);
my %WebhookCall;
{
    no warnings 'redefine';
    local *Kernel::System::WebUserAgent::Request = sub {
        my ( $Self, %Param ) = @_; %WebhookCall = %Param; return ( Status => '202 Accepted', Content => \q{} );
    };
    my $Webhook = $Dispatcher->_Webhook( {
        ID => 9002, TenantID => $TenantA, At => '2026-07-27 12:34:56',
        Payload => { TenantID => $TenantA, RequestID => $Integrated->{Data}->{RequestID}, Target => 'audit-hook', Trigger => 'warning', ObjectiveKey => 'resolution' },
    } );
    ok( $Webhook->{Success}, 'allow-listed HTTPS webhook is delivered' );
}
like( $WebhookCall{Header}->{'X-D724-Signature-256'}, qr{\Asha256=[0-9a-f]{64}\z}, 'webhook carries an HMAC SHA-256 signature' );
is( $WebhookCall{Header}->{'X-D724-Signature-Version'}, 'v1', 'webhook declares its signature contract version' );
is( $WebhookCall{Header}->{'X-D724-Signature-Timestamp'}, '2026-07-27 12:34:56', 'webhook signature includes a replay-window timestamp' );
is( $WebhookCall{Header}->{'X-D724-Delivery-ID'}, 9002, 'webhook carries stable delivery identifier' );
is( $WebhookCall{Header}->{'X-D724-Tenant'}, $TenantA, 'webhook carries the tenant boundary as signed-delivery context' );
is(
    $WebhookCall{Header}->{'X-D724-Signature-256'},
    'sha256=' . hmac_sha256_hex( 'v1.2026-07-27 12:34:56.9002.' . $WebhookCall{RawData}, '0123456789abcdef0123456789abcdef' ),
    'receiver can verify version, timestamp, delivery ID, and canonical payload as one signed message',
);
is( $WebhookCall{Header}->{'Content-Type'}, 'application/json', 'webhook sends canonical JSON instead of form encoding' );
is(
    $Dispatcher->_Webhook( { ID => 9003, TenantID => $TenantA, Payload => { TenantID => $TenantA, RequestID => 1, Target => 'missing-hook' } } )->{Error},
    'WEBHOOK_NOT_CONFIGURED', 'unknown webhook key fails closed without arbitrary URL access',
);
my $Fulfilled = $RequestObject->TaskUpdate(
    UserID => $AdminID, TenantID => $TenantA, TaskID => $IntegratedTask->{TaskID},
    ExpectedVersion => $IntegratedTask->{Version}, Status => 'completed', Comment => 'Done',
);
ok( $Fulfilled->{Success}, 'request fulfillment completes through normal task API' );
is(
    $Commitment->AgentGetByRequest( UserID => $AdminID, TenantID => $TenantA, RequestID => $Integrated->{Data}->{RequestID} )->{Data}->{Status},
    'met', 'request fulfillment automatically records commitment as met',
);

my $EntitlementSchema = $Catalog->CatalogItemSchemaSet(
    %CatalogCall, CatalogItemID => $Item->{Data}->{CatalogItemID}, ExpectedVersion => 2,
    Schema => {
        version => 3,
        fields => [ {
            key => 'support_tier', label => 'Support tier', type => 'select', required => 1,
            options => [ { value => 'standard', label => 'Standard' }, { value => 'premium', label => 'Premium' } ],
        } ],
        workflow => {
            approval => { required => 1, approver_role => 'tenant_admin' },
            fulfillment => [ { key => 'fulfill', name => 'Fulfill request', type => 'manual' } ],
            commitment => {
                default_policy_key => 'standard-resolution',
                entitlements => [ { key => 'premium-tier', answer_key => 'support_tier', equals => 'premium', policy_key => 'premium-multi' } ],
            },
        },
    },
);
ok( $EntitlementSchema->{Success}, 'catalog stores validated answer-based entitlement selection' );
my $Entitled = $RequestObject->CustomerSubmit(
    CustomerUserID => "customer-$Suffix\@example.test", CustomerID => $TenantA,
    CatalogItemID => $Item->{Data}->{CatalogItemID}, IdempotencyKey => "commit-$Suffix-entitled-0001", Answers => { support_tier => 'premium' },
);
ok( $Entitled->{Success}, 'premium request is submitted through request API' );
is( $Entitled->{Data}->{Workflow}->{commitment}->{policy_key}, 'premium-multi', 'validated answer selects premium policy snapshot' );
my $EntitledCustomer = $RequestObject->CustomerGet(
    CustomerUserID => "customer-$Suffix\@example.test", CustomerID => $TenantA, RequestID => $Entitled->{Data}->{RequestID},
);
is( scalar @{ $EntitledCustomer->{Data}->{Commitments} }, 2, 'customer initially sees response and resolution objectives' );
is( [ map { $_->{Status} } @{ $EntitledCustomer->{Data}->{Commitments} } ], [qw(paused paused)], 'approval pause rule applies to both initial objectives' );
my $EntitledApproval = $Entitled->{Data}->{Approvals}->[0];
my $EntitledApproved = $RequestObject->ApprovalDecide(
    UserID => $AdminID, TenantID => $TenantA, RequestID => $Entitled->{Data}->{RequestID},
    ExpectedVersion => $EntitledApproval->{Version}, Decision => 'approved', Comment => 'Premium entitlement approved',
);
ok( $EntitledApproved->{Success}, 'normal approval signal starts OLA and resumes objectives' );
my ($EntitledAgent) = grep { $_->{RequestID} == $Entitled->{Data}->{RequestID} } @{
    $RequestObject->AgentList( UserID => $AdminID, TenantID => $TenantA )->{Data}
};
is( scalar @{ $EntitledAgent->{Commitments} }, 3, 'agent sees response, resolution, and OLA objectives' );
ok( $RequestObject->ResponseRecord( UserID => $AdminID, TenantID => $TenantA, RequestID => $Entitled->{Data}->{RequestID} )->{Success}, 'agent response signal completes response objective' );
my $EntitledTask = $EntitledApproved->{Data}->{Tasks}->[0];
ok(
    $RequestObject->TaskUpdate(
        UserID => $AdminID, TenantID => $TenantA, TaskID => $EntitledTask->{TaskID}, ExpectedVersion => $EntitledTask->{Version}, Status => 'completed', Comment => 'Premium fulfilled',
    )->{Success},
    'normal fulfillment signal completes remaining objectives',
);
my $EntitledFinal = $Commitment->AgentListByRequest( UserID => $AdminID, TenantID => $TenantA, RequestID => $Entitled->{Data}->{RequestID} );
is( [ map { $_->{Status} } @{ $EntitledFinal->{Data} } ], [qw(met met met)], 'all premium objectives finish met in end-to-end lifecycle' );

my $GuardedCommitmentID = $EntitledFinal->{Data}->[0]->{CommitmentID};
my $GuardedVersion = $EntitledFinal->{Data}->[0]->{Version};
my ( $Running, $InactiveTenant ) = ( 'running', 'inactive' );
ok(
    $DBObject->Do(
        SQL => 'UPDATE d724_commitment_instance SET status = ? WHERE tenant_id = ? AND id = ?',
        Bind => [ \$Running, \$TenantA, \$GuardedCommitmentID ],
    ),
    'daemon guard commitment fixture is made runnable',
);
ok(
    $DBObject->Do( SQL => 'UPDATE d724_tenant SET status = ? WHERE key_name = ?', Bind => [ \$InactiveTenant, \$TenantA ] ),
    'tenant is deactivated before scheduler execution',
);
my $DeniedSweep = $Commitment->Sweep( At => '2035-01-01 00:00:00' );
ok( !$DeniedSweep->{Success}, 'scheduler fails closed when work references an inactive tenant' );
ok( $DeniedSweep->{Counts}->{Denied} >= 1, 'scheduler reports policy-denied tenant work' );
$DBObject->Prepare(
    SQL => 'SELECT status, version FROM d724_commitment_instance WHERE tenant_id = ? AND id = ?',
    Bind => [ \$TenantA, \$GuardedCommitmentID ], Limit => 1,
);
is( [ $DBObject->FetchrowArray() ], [ 'running', $GuardedVersion ], 'denied scheduler work cannot mutate commitment state/version' );

my ( $Pending, $DispatchAt, $EmptyLease ) = ( 'pending', '2035-01-01 00:00:00', q{} );
ok(
    $DBObject->Do(
        SQL => 'UPDATE d724_escalation_outbox SET status = ?, available_time = ?, lease_token = ?, lease_until = NULL WHERE id = ?',
        Bind => [ \$Pending, \$DispatchAt, \$EmptyLease, \$EscalationID ],
    ),
    'daemon guard outbox fixture is made dispatchable',
);
my $DeniedDispatch = $Dispatcher->Dispatch( At => $DispatchAt, WorkerID => 'inactive-tenant-guard', Handlers => {} );
ok( !$DeniedDispatch->{Success}, 'dispatcher fails closed for inactive tenant work' );
ok( $DeniedDispatch->{Counts}->{Denied} >= 1, 'dispatcher reports policy-denied outbox work' );
$DBObject->Prepare( SQL => 'SELECT status, lease_token FROM d724_escalation_outbox WHERE id = ?', Bind => [ \$EscalationID ], Limit => 1 );
is( [ $DBObject->FetchrowArray() ], [ 'pending', q{} ], 'denied delivery remains unclaimed and unchanged' );

$Helper->ConfigSettingChange( Key => 'D724::Commitment::Enabled', Value => 0 );
is(
    $Commitment->PolicyList( Subject => $Subject, TenantID => $TenantA )->{Error},
    'COMMITMENT_DISABLED', 'commitment APIs fail closed when disabled',
);

done_testing;
