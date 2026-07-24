# --
# Copyright (C) 2026 Data Market Bilgi Hizmetleri A.S.
# SPDX-License-Identifier: GPL-3.0-only
# --
use v5.24;
use strict;
use warnings;
use Test2::V0;
use Kernel::System::UnitTest::RegisterOM;

$Kernel::OM->ObjectParamAdd( 'Kernel::System::UnitTest::Helper' => { RestoreDatabase => 1 } );
my $Helper = $Kernel::OM->Get('Kernel::System::UnitTest::Helper');
for my $Setting (
    [ 'D724::Webhook::Enabled', 1 ], [ 'D724::Webhook::ScanBatchSize', 100 ],
    [ 'D724::Audit::Enabled', 1 ], [ 'D724::TenantGuard::Enabled', 1 ],
    [ 'D724::Commitment::EscalationDispatchEnabled', 1 ], [ 'D724::Commitment::EscalationMaxAttempts', 3 ],
    [ 'D724::Commitment::WebhookAllowedHosts', ['hooks.example.test'] ],
    [ 'D724::Commitment::WebhookEndpoints', { 'lifecycle::URL' => 'https://hooks.example.test/lifecycle', 'lifecycle::Secret' => '0123456789abcdef0123456789abcdef' } ],
) {
    $Helper->ConfigSettingChange( Key => $Setting->[0], Value => $Setting->[1] );
}

my $Suffix = lc $Helper->GetRandomID();
my $TenantA = "webhook-a-$Suffix";
my $TenantB = "webhook-b-$Suffix";
my $DB = $Kernel::OM->Get('Kernel::System::DB');
for my $Tenant ( $TenantA, $TenantB ) {
    my @Values = ( $Tenant, "Webhook $Tenant", 1, 1 ); my @Bind = map { \$_ } @Values;
    ok( $DB->Do(
        SQL => "INSERT INTO d724_tenant (key_name, name, status, version, create_time, create_by, change_time, change_by) VALUES (?, ?, 'active', 1, current_timestamp, ?, current_timestamp, ?)",
        Bind => \@Bind,
    ), "tenant fixture $Tenant created" );
}

my $Admin = { ID => 'agent:webhook-admin', TenantIDs => [$TenantA], RoleBindings => { $TenantA => ['tenant_admin'] } };
my $Other = { ID => 'agent:webhook-other', TenantIDs => [$TenantB], RoleBindings => { $TenantB => ['tenant_admin'] } };
my $Webhook = $Kernel::OM->Get('Kernel::System::D724::Webhook');
my $Audit = $Kernel::OM->Get('Kernel::System::D724::Audit');
my $Dispatcher = $Kernel::OM->Get('Kernel::System::D724::EscalationDispatcher');

is(
    $Webhook->SubscriptionCreate(
        Subject => $Admin, TenantID => $TenantA, Key => 'missing', Name => 'Missing endpoint',
        EndpointKey => 'missing', EventPatterns => ['request.*'], StartSequence => 0,
    )->{Error},
    'ENDPOINT_NOT_CONFIGURED', 'subscription cannot reference an arbitrary endpoint',
);
my $Created = $Webhook->SubscriptionCreate(
    Subject => $Admin, TenantID => $TenantA, Key => 'request-events', Name => 'Request lifecycle',
    EndpointKey => 'lifecycle', EventPatterns => ['request.*'], StartSequence => 0,
);
ok( $Created->{Success}, 'tenant administrator creates lifecycle subscription' );
is( $Created->{Data}->{CursorSequence}, 0, 'explicit zero cursor enables authorized catch-up' );
is(
    $Webhook->SubscriptionGet( Subject => $Other, TenantID => $TenantA, SubscriptionID => $Created->{Data}->{SubscriptionID} )->{Error},
    'FORBIDDEN', 'another tenant cannot discover a subscription',
);

ok( $Audit->Record(
    TenantID => $TenantA, ActorType => 'customer', ActorID => 'customer:webhook-test',
    Action => 'request.created', ObjectType => 'request', ObjectID => '7001', CorrelationID => 'REQ-WEBHOOK-7001',
    DedupeKey => "webhook-test:$Suffix:request-created", FromState => 'initializing', ToState => 'awaiting_approval',
    Outcome => 'success', Details => { catalog_item_id => 17 },
)->{Success}, 'normalized lifecycle event appended to immutable audit chain' );
ok( $Audit->Record(
    TenantID => $TenantA, ActorType => 'agent', ActorID => 'agent:webhook-admin',
    Action => 'catalog.item_updated', ObjectType => 'catalog_item', ObjectID => '17', CorrelationID => 'CAT-17',
    DedupeKey => "webhook-test:$Suffix:catalog-updated", FromState => 'active', ToState => 'active',
    Outcome => 'success', Details => { version => 2 },
)->{Success}, 'non-matching audit event appended' );

my $Scanned = $Webhook->Scan( Limit => 100 );
ok( $Scanned->{Success}, 'scanner advances active subscription' );
is( $Scanned->{Counts}->{Matched}, 1, 'only request wildcard event matches' );
is( $Scanned->{Counts}->{Queued}, 1, 'one signed delivery is queued' );
my $AfterScan = $Webhook->SubscriptionGet(
    Subject => $Admin, TenantID => $TenantA, SubscriptionID => $Created->{Data}->{SubscriptionID},
);
is( $AfterScan->{Data}->{CursorSequence}, 3, 'cursor advances across matching and non-matching audit events' );

my $ActionKey = 'webhooksub' . $Created->{Data}->{SubscriptionID};
$DB->Prepare(
    SQL => "SELECT id, status, payload_json FROM d724_escalation_outbox WHERE tenant_id = ? AND commitment_id = 0 AND action_key = ?",
    Bind => [ \$TenantA, \$ActionKey ], Limit => 1,
);
my ( $OutboxID, $OutboxStatus, $PayloadJSON ) = $DB->FetchrowArray();
ok( $OutboxID, 'shared delivery outbox contains subscription event' );
is( $OutboxStatus, 'pending', 'new lifecycle delivery starts pending' );
my $Payload = $Kernel::OM->Get('Kernel::System::JSON')->Decode( Data => $PayloadJSON );
is( $Payload->{Event}->{Action}, 'request.created', 'delivery payload retains normalized action' );
is( $Payload->{Event}->{ObjectID}, '7001', 'delivery payload retains tenant-scoped object identity' );
is( $Payload->{SubscriptionID}, $Created->{Data}->{SubscriptionID}, 'delivery identifies its subscription resource' );
is( $Payload->{SubscriptionKey}, 'request-events', 'delivery identifies its subscription contract' );

my $ReplayScan = $Webhook->Scan( Limit => 100 );
is( $ReplayScan->{Counts}->{Scanned}, 0, 'repeat scan has no cursor work' );
my $Rewind = 1;
ok( $DB->Do(
    SQL => 'UPDATE d724_webhook_subscription SET cursor_sequence = ? WHERE tenant_id = ? AND id = ?',
    Bind => [ \$Rewind, \$TenantA, \$Created->{Data}->{SubscriptionID} ],
), 'crash-window cursor rewind simulated' );
my $RecoveredScan = $Webhook->Scan( Limit => 100 );
ok( $RecoveredScan->{Success}, 'scanner recovers from an outbox-before-cursor crash window' );
is( $RecoveredScan->{Counts}->{Replayed}, 1, 'existing subscription-sequence delivery is recognized as replay' );
is( $RecoveredScan->{Counts}->{Queued}, 0, 'crash recovery creates no second delivery' );
$DB->Prepare(
    SQL => 'SELECT COUNT(*) FROM d724_escalation_outbox WHERE tenant_id = ? AND commitment_id = 0 AND action_key = ?',
    Bind => [ \$TenantA, \$ActionKey ],
);
my ($DeliveryCount) = $DB->FetchrowArray();
is( $DeliveryCount, 1, 'subscription and audit sequence remain exactly-once in the outbox' );

my $Delivered = $Dispatcher->Dispatch(
    At => '2030-01-01 00:00:00', Limit => 10, WorkerID => 'webhook-subscription-test',
    Handlers => { webhook => sub {
        my ($Row) = @_;
        return { Success => 0, Error => 'WRONG_DELIVERY' } if $Row->{ID} != $OutboxID || $Row->{TenantID} ne $TenantA;
        return { Success => 1, DeliveryRef => "subscription:$OutboxID", ResponseCode => '202' };
    } },
);
is( $Delivered->{Counts}->{Delivered}, 1, 'shared leased dispatcher delivers lifecycle event' );

my $Updated = $Webhook->SubscriptionUpdate(
    Subject => $Admin, TenantID => $TenantA, SubscriptionID => $Created->{Data}->{SubscriptionID},
    ExpectedVersion => 1, Status => 'inactive',
);
ok( $Updated->{Success}, 'tenant administrator disables subscription optimistically' );
is( $Updated->{Data}->{Status}, 'inactive', 'inactive subscription is persisted' );
is(
    $Webhook->SubscriptionUpdate(
        Subject => $Admin, TenantID => $TenantA, SubscriptionID => $Created->{Data}->{SubscriptionID},
        ExpectedVersion => 1, Status => 'active',
    )->{Error},
    'VERSION_CONFLICT', 'stale subscription update is rejected',
);
my $Second = $Webhook->SubscriptionCreate(
    Subject => $Admin, TenantID => $TenantA, Key => 'approval-events', Name => 'Approval lifecycle',
    EndpointKey => 'lifecycle', EventPatterns => ['approval.*'], Status => 'inactive',
);
ok( $Second->{Success}, 'same tenant creates a second inactive subscription' );
is(
    scalar @{ $Webhook->SubscriptionList( Subject => $Admin, TenantID => $TenantA )->{Data} },
    2, 'subscription list retains every ID before loading row details',
);

done_testing;
