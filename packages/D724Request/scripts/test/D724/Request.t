# --
# CareOnCloud ESM enterprise service management platform.
# Copyright (C) 2026 Data Market Bilgi Hizmetleri A.S.
# SPDX-License-Identifier: GPL-3.0-only
# --

use v5.24;
use strict;
use warnings;
use utf8;

use Test2::V0;
use Kernel::System::UnitTest::RegisterOM;

$Kernel::OM->ObjectParamAdd(
    'Kernel::System::UnitTest::Helper' => { RestoreDatabase => 1 },
);
my $Helper = $Kernel::OM->Get('Kernel::System::UnitTest::Helper');
$Helper->ConfigSettingChange( Key => 'D724::Catalog::Enabled', Value => 1 );
$Helper->ConfigSettingChange( Key => 'D724::Request::Enabled', Value => 1 );
$Helper->ConfigSettingChange( Key => 'D724::Audit::Enabled', Value => 1 );
$Helper->ConfigSettingChange( Key => 'CheckEmailAddresses', Value => 0 );

my $Suffix  = lc $Helper->GetRandomID();
my $TenantA = "request-a-$Suffix";
my $TenantB = "request-b-$Suffix";
my $UserObject = $Kernel::OM->Get('Kernel::System::User');
my $AdminID = $UserObject->UserAdd(
    UserFirstname => 'Request', UserLastname => 'Admin', UserLogin => "request-admin-$Suffix",
    UserEmail => "request-admin-$Suffix\@example.test", ValidID => 1, ChangeUserID => 1,
) || die 'Could not create request admin';
my $OtherID = $UserObject->UserAdd(
    UserFirstname => 'Other', UserLastname => 'Agent', UserLogin => "request-other-$Suffix",
    UserEmail => "request-other-$Suffix\@example.test", ValidID => 1, ChangeUserID => 1,
) || die 'Could not create other agent';

my $DBObject = $Kernel::OM->Get('Kernel::System::DB');
for my $Tenant ( $TenantA, $TenantB ) {
    my @Values = ( $Tenant, "Tenant $Tenant", 'active', 1, $AdminID, $AdminID );
    my @Bind = map { \$_ } @Values;
    ok(
        $DBObject->Do(
            SQL => 'INSERT INTO d724_tenant (key_name, name, status, version, create_time, create_by, change_time, change_by) VALUES (?, ?, ?, ?, current_timestamp, ?, current_timestamp, ?)',
            Bind => \@Bind,
        ),
        "$Tenant directory row created",
    );
}
for my $Role ( [ $TenantA, $AdminID, 'tenant_admin' ], [ $TenantB, $OtherID, 'agent' ] ) {
    my @Values = ( @{$Role}, 'active', $AdminID, $AdminID );
    my @Bind = map { \$_ } @Values;
    ok(
        $DBObject->Do(
            SQL => 'INSERT INTO d724_tenant_agent_role (tenant_id, user_id, role_name, status, create_time, create_by, change_time, change_by) VALUES (?, ?, ?, ?, current_timestamp, ?, current_timestamp, ?)',
            Bind => \@Bind,
        ),
        "membership $Role->[2] created",
    );
}

my $Catalog = $Kernel::OM->Get('Kernel::System::D724::Catalog');
my $AdminSubject = { ID => "agent:$AdminID", TenantIDs => [$TenantA], RoleBindings => { $TenantA => ['tenant_admin'] } };
my %CatalogBase = ( Subject => $AdminSubject, TenantID => $TenantA, UserID => $AdminID );
my $Service = $Catalog->ServiceCreate( %CatalogBase, Key => 'workplace', Name => 'Workplace', Status => 'active' );
my $Offering = $Catalog->OfferingCreate(
    %CatalogBase, ServiceID => $Service->{Data}->{ServiceID}, Key => 'device', Name => 'Device', Status => 'active',
);
my $Item = $Catalog->CatalogItemCreate(
    %CatalogBase, OfferingID => $Offering->{Data}->{OfferingID}, Key => 'laptop', Name => 'Laptop', Status => 'active',
);
ok( $Item->{Success}, 'requestable catalog item created' );
my $Schema = {
    version => 1,
    workflow => {
        approval => { required => 1, approver_role => 'tenant_admin' },
        fulfillment => [ { key => 'prepare', name => 'Dizüstü bilgisayarı hazırla', type => 'manual' } ],
    },
    fields => [
        { key => 'reason', label => 'Reason', type => 'textarea', required => 1 },
        { key => 'model', label => 'Model', type => 'select', required => 1, options => [
            { value => 'standard', label => 'Standard' }, { value => 'developer', label => 'Developer' },
        ] },
        { key => 'accessories', label => 'Accessories', type => 'multiselect', options => [
            { value => 'dock', label => 'Dock' }, { value => 'mouse', label => 'Mouse' },
        ] },
    ],
};
ok(
    $Catalog->CatalogItemSchemaSet( %CatalogBase, CatalogItemID => $Item->{Data}->{CatalogItemID}, Schema => $Schema )->{Success},
    'approval and fulfillment schema created',
);

my $Request = $Kernel::OM->Get('Kernel::System::D724::Request');
my %Customer = ( CustomerUserID => "customer-$Suffix\@example.test", CustomerID => $TenantA );
my %Answers = ( reason => 'Mühendislik iş istasyonu — İstanbul', model => 'developer', accessories => ['dock'] );
my $Created = $Request->CustomerSubmit(
    %Customer, CatalogItemID => $Item->{Data}->{CatalogItemID}, IdempotencyKey => "submit-$Suffix-00000001", Answers => \%Answers,
);
ok( $Created->{Success}, 'customer request created' );
is( $Created->{Data}->{Answers}->{reason}, 'Mühendislik iş istasyonu — İstanbul', 'Unicode answers survive canonical payload hashing' );
is( $Created->{Data}->{Status}, 'awaiting_approval', 'request waits for approval' );
is( $Created->{Data}->{Approvals}->[0]->{Status}, 'pending', 'approval is pending' );
is( $Created->{Data}->{Tasks}->[0]->{Status}, 'blocked', 'fulfillment is blocked before approval' );
is( $Created->{Data}->{Answers}, \%Answers, 'validated answers are persisted' );

my $Replay = $Request->CustomerSubmit(
    %Customer, CatalogItemID => $Item->{Data}->{CatalogItemID}, IdempotencyKey => "submit-$Suffix-00000001", Answers => \%Answers,
);
ok( $Replay->{IdempotentReplay}, 'identical retry is an idempotent replay' );
is( $Replay->{Data}->{RequestID}, $Created->{Data}->{RequestID}, 'retry returns original request' );
is(
    $Request->CustomerSubmit(
        %Customer, CatalogItemID => $Item->{Data}->{CatalogItemID}, IdempotencyKey => "submit-$Suffix-00000001",
        Answers => { %Answers, model => 'standard' },
    )->{Error},
    'IDEMPOTENCY_CONFLICT', 'same key cannot represent a different payload',
);

is(
    $Request->CustomerSubmit(
        %Customer, CatalogItemID => $Item->{Data}->{CatalogItemID}, IdempotencyKey => "submit-$Suffix-missing1",
        Answers => { model => 'developer' },
    )->{Error},
    'ANSWER_REQUIRED', 'required answers are enforced server-side',
);
is(
    $Request->CustomerSubmit(
        %Customer, CatalogItemID => $Item->{Data}->{CatalogItemID}, IdempotencyKey => "submit-$Suffix-option01",
        Answers => { %Answers, model => 'root-shell' },
    )->{Error},
    'ANSWER_OPTION_INVALID', 'select values are allow-listed',
);
is(
    $Request->CustomerSubmit(
        %Customer, CatalogItemID => $Item->{Data}->{CatalogItemID}, IdempotencyKey => "submit-$Suffix-unknown1",
        Answers => { %Answers, injected => 'value' },
    )->{Error},
    'ANSWER_UNKNOWN', 'unknown answer keys are rejected',
);
is(
    $Request->CustomerSubmit(
        CustomerUserID => $Customer{CustomerUserID}, CustomerID => $TenantB,
        CatalogItemID => $Item->{Data}->{CatalogItemID}, IdempotencyKey => "submit-$Suffix-cross001", Answers => \%Answers,
    )->{Error},
    'NOT_FOUND', 'catalog item IDs do not cross tenant boundaries',
);

my $Own = $Request->CustomerGet( %Customer, RequestID => $Created->{Data}->{RequestID} );
ok( $Own->{Success}, 'customer reads own request' );
is(
    $Request->CustomerGet(
        CustomerUserID => "different-$Suffix\@example.test", CustomerID => $TenantA, RequestID => $Created->{Data}->{RequestID},
    )->{Error},
    'NOT_FOUND', 'another customer cannot read the request',
);
is(
    $Request->AgentList( UserID => $OtherID, TenantID => $TenantA )->{Error},
    'FORBIDDEN', 'agent from another tenant cannot list requests',
);

my $Approval = $Created->{Data}->{Approvals}->[0];
my $IntegrationAdmin = {
    ID => "integration:lifecycle-$Suffix", TenantIDs => [$TenantA],
    RoleBindings => { $TenantA => ['tenant_admin'] },
};
is(
    $Request->ApprovalDecide(
        TenantID => $TenantA, RequestID => $Created->{Data}->{RequestID},
        ExpectedVersion => $Approval->{Version}, Decision => 'approved',
        IntegrationSubject => { %{$IntegrationAdmin}, TenantIDs => [$TenantB] },
    )->{Error},
    'INTEGRATION_SUBJECT_INVALID', 'integration subject cannot cross the request tenant boundary',
);
my $Approved = $Request->ApprovalDecide(
    IntegrationSubject => $IntegrationAdmin, TenantID => $TenantA, RequestID => $Created->{Data}->{RequestID},
    ExpectedVersion => $Approval->{Version}, Decision => 'approved', Comment => 'Approved for engineering.',
);
ok( $Approved->{Success}, 'tenant-admin integration approves request' );
is( $Approved->{Data}->{Status}, 'in_fulfillment', 'approved request enters fulfillment' );
is( $Approved->{Data}->{Tasks}->[0]->{Status}, 'pending', 'approval releases fulfillment task' );
ok(
    $Request->ApprovalDecide(
        IntegrationSubject => $IntegrationAdmin, TenantID => $TenantA, RequestID => $Created->{Data}->{RequestID},
        ExpectedVersion => $Approval->{Version}, Decision => 'approved', Comment => 'Approved for engineering.',
    )->{IdempotentReplay},
    'identical integration approval retry is a safe replay',
);
is(
    $Request->ApprovalDecide(
        IntegrationSubject => $IntegrationAdmin, TenantID => $TenantA, RequestID => $Created->{Data}->{RequestID},
        ExpectedVersion => $Approval->{Version}, Decision => 'rejected', Comment => q{},
    )->{Error},
    'TRANSITION_INVALID', 'decided approval cannot be overwritten',
);

my $Task = $Approved->{Data}->{Tasks}->[0];
my $Started = $Request->TaskUpdate(
    IntegrationSubject => $IntegrationAdmin, TenantID => $TenantA, TaskID => $Task->{TaskID}, ExpectedVersion => $Task->{Version},
    Status => 'in_progress', Comment => 'Imaging device.',
);
is( $Started->{Data}->{Tasks}->[0]->{Status}, 'in_progress', 'task starts with valid transition' );
ok(
    $Request->TaskUpdate(
        IntegrationSubject => $IntegrationAdmin, TenantID => $TenantA, TaskID => $Task->{TaskID}, ExpectedVersion => $Task->{Version},
        Status => 'in_progress', Comment => 'Imaging device.',
    )->{IdempotentReplay},
    'identical integration task retry is a safe replay',
);
is(
    $Request->TaskUpdate(
        IntegrationSubject => $IntegrationAdmin, TenantID => $TenantA, TaskID => $Task->{TaskID}, ExpectedVersion => $Task->{Version},
        Status => 'completed', Comment => q{},
    )->{Error},
    'VERSION_CONFLICT', 'stale task update is rejected',
);
my $CurrentTask = $Started->{Data}->{Tasks}->[0];
my $Completed = $Request->TaskUpdate(
    IntegrationSubject => $IntegrationAdmin, TenantID => $TenantA, TaskID => $CurrentTask->{TaskID}, ExpectedVersion => $CurrentTask->{Version},
    Status => 'completed', Comment => 'Delivered.',
);
is( $Completed->{Data}->{Status}, 'fulfilled', 'last completed task fulfills request' );
is(
    $Request->TaskUpdate(
        IntegrationSubject => $IntegrationAdmin, TenantID => $TenantA, TaskID => $CurrentTask->{TaskID}, ExpectedVersion => $CurrentTask->{Version} + 1,
        Status => 'failed', Comment => q{},
    )->{Error},
    'TRANSITION_INVALID', 'terminal task state cannot transition again',
);

my $Audit = $Kernel::OM->Get('Kernel::System::D724::Audit');
my $AuditList = $Audit->List( UserID => $AdminID, TenantID => $TenantA, Limit => 100 );
ok( $AuditList->{Success}, 'tenant admin reads normalized request audit events' );
my @RequestAudit = grep {
    $_->{CorrelationID} eq $Created->{Data}->{RequestNumber}
} @{ $AuditList->{Data} };
is(
    [ map { $_->{Action} } @RequestAudit ],
    [qw(request.created request.approved task.status_changed task.status_changed request.fulfilled)],
    'request lifecycle emits ordered normalized audit vocabulary',
);
my $FirstRequestSequence = $RequestAudit[0]->{Sequence};
is( [ map { $_->{Sequence} } @RequestAudit ], [ $FirstRequestSequence .. $FirstRequestSequence + 4 ], 'request audit sequence is contiguous within the tenant chain' );
is( scalar( grep { $_->{Action} eq 'request.created' } @RequestAudit ), 1, 'idempotent replay does not duplicate creation audit' );
is(
    scalar( grep { $_->{ActorType} eq 'integration' } @RequestAudit ), 4,
    'all four lifecycle mutation events retain the integration actor type',
);
is( $Audit->List( UserID => $OtherID, TenantID => $TenantB )->{Error}, 'FORBIDDEN', 'non-auditor cannot export tenant audit' );
ok( $Audit->Verify( UserID => $AdminID, TenantID => $TenantA )->{Valid}, 'request lifecycle audit chain verifies' );

$Helper->ConfigSettingChange( Key => 'D724::Request::Enabled', Value => 0 );
is(
    $Request->CustomerGet( %Customer, RequestID => $Created->{Data}->{RequestID} )->{Error},
    'REQUEST_DISABLED', 'request APIs fail closed when disabled',
);

done_testing;
