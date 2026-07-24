# --
# D724 ESM is an enterprise service management platform based on OTOBO.
# Copyright (C) 2026 Data Market Bilgi Hizmetleri A.S.
# SPDX-License-Identifier: GPL-3.0-only
# --

use v5.24;
use strict;
use warnings;
use utf8;
use Test2::V0;
use Kernel::System::UnitTest::RegisterOM;

$Kernel::OM->ObjectParamAdd( 'Kernel::System::UnitTest::Helper' => { RestoreDatabase => 1 } );
my $Helper = $Kernel::OM->Get('Kernel::System::UnitTest::Helper');
$Helper->ConfigSettingChange( Key => 'D724::Catalog::Enabled', Value => 1 );
$Helper->ConfigSettingChange( Key => 'D724::Request::Enabled', Value => 1 );
$Helper->ConfigSettingChange( Key => 'D724::Commitment::Enabled', Value => 1 );
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
for my $Tenant ( $TenantA, $TenantB ) {
    my @Values = ( $Tenant, "Tenant $Tenant", 'active', 1, $AdminID, $AdminID ); my @Bind = map { \$_ } @Values;
    $DBObject->Do(
        SQL => 'INSERT INTO d724_tenant (key_name, name, status, version, create_time, create_by, change_time, change_by) VALUES (?, ?, ?, ?, current_timestamp, ?, current_timestamp, ?)', Bind => \@Bind,
    ) || die 'Could not create tenant';
}
for my $Role ( [ $TenantA, $AdminID, 'tenant_admin' ], [ $TenantB, $OtherID, 'agent' ] ) {
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
my $Fulfilled = $RequestObject->TaskUpdate(
    UserID => $AdminID, TenantID => $TenantA, TaskID => $IntegratedTask->{TaskID},
    ExpectedVersion => $IntegratedTask->{Version}, Status => 'completed', Comment => 'Done',
);
ok( $Fulfilled->{Success}, 'request fulfillment completes through normal task API' );
is(
    $Commitment->AgentGetByRequest( UserID => $AdminID, TenantID => $TenantA, RequestID => $Integrated->{Data}->{RequestID} )->{Data}->{Status},
    'met', 'request fulfillment automatically records commitment as met',
);

$Helper->ConfigSettingChange( Key => 'D724::Commitment::Enabled', Value => 0 );
is(
    $Commitment->PolicyList( Subject => $Subject, TenantID => $TenantA )->{Error},
    'COMMITMENT_DISABLED', 'commitment APIs fail closed when disabled',
);

done_testing;
