# --
# CareOnCloud ESM enterprise service management platform.
# Copyright (C) 2026 Data Market Bilgi Hizmetleri A.S.
# SPDX-License-Identifier: GPL-3.0-only
# --

package Kernel::System::CareOnCloud::EscalationDispatcher;

use v5.24;
use strict;
use warnings;
use Digest::SHA qw(hmac_sha256_hex sha256_hex);
use URI ();

our $VERSION = '0.5.0';
our @ObjectDependencies = (
    'Kernel::Config',
    'Kernel::System::DB',
    'Kernel::System::CareOnCloud::Audit',
    'Kernel::System::CareOnCloud::TenantGuard',
    'Kernel::System::Email',
    'Kernel::System::JSON',
    'Kernel::System::User',
    'Kernel::System::WebUserAgent',
);

sub new { return bless {}, $_[0] }

sub Dispatch {
    my ( $Self, %Param ) = @_;
    my $Config = $Kernel::OM->Get('Kernel::Config');
    return { Success => 0, Error => 'DISPATCH_DISABLED' } if !$Config->Get('CareOnCloud::Commitment::EscalationDispatchEnabled');
    my $At = $Self->_TimeNormalize( $Param{At} );
    return { Success => 0, Error => 'TIME_INVALID' } if !$At;
    my $Limit = $Param{Limit} // $Config->Get('CareOnCloud::Commitment::EscalationBatchSize') // 25;
    return { Success => 0, Error => 'LIMIT_INVALID' } if $Limit !~ m{\A[1-9][0-9]*\z}smx || $Limit > 100;
    my $Worker = $Param{WorkerID} // "dispatcher:$$";
    return { Success => 0, Error => 'WORKER_INVALID' } if $Worker !~ m{\A[a-zA-Z0-9_.:-]{1,64}\z}smx;
    my $DB = $Kernel::OM->Get('Kernel::System::DB');
    $DB->Do(
        SQL => "UPDATE careoncloud_escalation_outbox SET status = 'retry', lease_token = '', lease_until = NULL, last_error = 'LEASE_EXPIRED', change_time = current_timestamp WHERE status = 'processing' AND lease_until < ?",
        Bind => [ \$At ],
    );
    $DB->Prepare(
        SQL => "SELECT id, tenant_id FROM careoncloud_escalation_outbox WHERE status IN ('pending','retry') AND available_time <= ? ORDER BY available_time, id",
        Bind => [ \$At ], Limit => $Limit,
    );
    my @Work; while ( my @Row = $DB->FetchrowArray() ) { push @Work, \@Row }
    my %Counts = ( Claimed => 0, Delivered => 0, Retried => 0, Dead => 0, Denied => 0, Errors => 0 );
    for my $Work (@Work) {
        my ( $ID, $TenantID ) = @{$Work};
        my $Automation = $Kernel::OM->Get('Kernel::System::CareOnCloud::TenantGuard')->AutomationAuthorize(
            TenantID => $TenantID, JobName => 'escalation-dispatch',
        );
        if ( !$Automation->{Success} ) { $Counts{Denied}++; $Counts{Errors}++; next }
        my $Token = sha256_hex( join q{:}, $Worker, $ID, $At, rand() );
        my $LeaseUntil = $Self->_AddSeconds( Time => $At, Seconds => 60 );
        $DB->Do(
            SQL => "UPDATE careoncloud_escalation_outbox SET status = 'processing', lease_token = ?, lease_until = ?, attempt_count = attempt_count + 1, lifetime_attempt_count = lifetime_attempt_count + 1, change_time = current_timestamp WHERE id = ? AND status IN ('pending','retry') AND available_time <= ?",
            Bind => [ \$Token, \$LeaseUntil, \$ID, \$At ],
        );
        my $Row = $Self->_ClaimedGet( ID => $ID, Token => $Token );
        next if !$Row;
        $Counts{Claimed}++;
        my $Result;
        eval { $Result = $Self->_Deliver( Row => $Row, Handlers => $Param{Handlers} ); 1 }
            or $Result = { Success => 0, Error => 'DELIVERY_EXCEPTION' };
        if ( $Result->{Success} ) {
            my $Ref = substr( $Result->{DeliveryRef} // q{}, 0, 255 );
            my $Code = substr( $Result->{ResponseCode} // 'OK', 0, 64 );
            $DB->Do(
                SQL => "UPDATE careoncloud_escalation_outbox SET status = 'delivered', processed_time = ?, lease_token = '', lease_until = NULL, delivery_ref = ?, response_code = ?, last_error = '', change_time = current_timestamp WHERE id = ? AND lease_token = ?",
                Bind => [ \$At, \$Ref, \$Code, \$ID, \$Token ],
            );
            $Counts{Delivered}++;
            next;
        }
        my $MaxAttempts = $Config->Get('CareOnCloud::Commitment::EscalationMaxAttempts') // 5;
        my $Dead = $Row->{AttemptCount} >= $MaxAttempts ? 1 : 0;
        my $Status = $Dead ? 'dead' : 'retry';
        my $Delay = 60 * ( 2 ** ( $Row->{AttemptCount} - 1 ) );
        $Delay = 3600 if $Delay > 3600;
        my $Available = $Self->_AddSeconds( Time => $At, Seconds => $Delay );
        my $Error = substr( $Result->{Error} // 'DELIVERY_FAILED', 0, 2000 );
        $DB->Do(
            SQL => "UPDATE careoncloud_escalation_outbox SET status = ?, available_time = ?, lease_token = '', lease_until = NULL, last_error = ?, response_code = ?, change_time = current_timestamp WHERE id = ? AND lease_token = ?",
            Bind => [ \$Status, \$Available, \$Error, \$Error, \$ID, \$Token ],
        );
        $Counts{ $Dead ? 'Dead' : 'Retried' }++;
    }
    return { Success => $Counts{Errors} ? 0 : 1, Counts => \%Counts };
}

sub QueueWebhook {
    my ( $Self, %Param ) = @_;
    return { Success => 0, Error => 'TENANT_ID_INVALID' }
        if ( $Param{TenantID} // q{} ) !~ m{\A[a-zA-Z0-9][a-zA-Z0-9._:-]{0,127}\z}smx;
    return { Success => 0, Error => 'SOURCE_SEQUENCE_INVALID' }
        if ( $Param{SourceSequence} // q{} ) !~ m{\A[1-9][0-9]*\z}smx;
    return { Success => 0, Error => 'ACTION_KEY_INVALID' }
        if ( $Param{ActionKey} // q{} ) !~ m{\A[a-z][a-z0-9_-]{0,63}\z}smx;
    return { Success => 0, Error => 'WEBHOOK_KEY_INVALID' }
        if ( $Param{EndpointKey} // q{} ) !~ m{\A[a-z][a-z0-9_-]{0,63}\z}smx;
    return { Success => 0, Error => 'PAYLOAD_INVALID' }
        if ref $Param{Payload} ne 'HASH' || ( $Param{Payload}->{TenantID} // q{} ) ne $Param{TenantID};
    my $At = $Self->_TimeNormalize( $Param{At} );
    return { Success => 0, Error => 'TIME_INVALID' } if !$At;
    my %Payload = ( %{ $Param{Payload} }, Target => $Param{EndpointKey} );
    my $PayloadJSON = $Kernel::OM->Get('Kernel::System::JSON')->Encode( Data => \%Payload, SortKeys => 1 );
    return { Success => 0, Error => 'PAYLOAD_TOO_LARGE' } if length $PayloadJSON > 8000;
    my $DB = $Kernel::OM->Get('Kernel::System::DB');
    $DB->Prepare(
        SQL => 'SELECT id, payload_json FROM careoncloud_escalation_outbox WHERE tenant_id = ? AND commitment_event_id = ? AND action_key = ?',
        Bind => [ \$Param{TenantID}, \$Param{SourceSequence}, \$Param{ActionKey} ], Limit => 1,
    );
    my ( $ExistingID, $ExistingPayload ) = $DB->FetchrowArray();
    if ($ExistingID) {
        return { Success => 0, Error => 'IDEMPOTENCY_CONFLICT' } if $ExistingPayload ne $PayloadJSON;
        return { Success => 1, Data => { OutboxID => 0 + $ExistingID }, IdempotentReplay => 1 };
    }
    my ( $CommitmentID, $Status, $Attempts, $Error ) = ( 0, 'pending', 0, q{} );
    my @Values = (
        $Param{TenantID}, $CommitmentID, $Param{SourceSequence}, $Param{ActionKey},
        'webhook', $PayloadJSON, $Status, $Attempts, $At, $Error,
    );
    my @Bind = map { \$_ } @Values;
    my $Inserted = $DB->Do(
        SQL => 'INSERT INTO careoncloud_escalation_outbox (tenant_id, commitment_id, commitment_event_id, action_key, action_type, payload_json, status, attempt_count, available_time, last_error, create_time, change_time) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, current_timestamp, current_timestamp)',
        Bind => \@Bind,
    );
    $DB->Prepare(
        SQL => 'SELECT id, payload_json FROM careoncloud_escalation_outbox WHERE tenant_id = ? AND commitment_event_id = ? AND action_key = ?',
        Bind => [ \$Param{TenantID}, \$Param{SourceSequence}, \$Param{ActionKey} ], Limit => 1,
    );
    my ( $ID, $StoredPayload ) = $DB->FetchrowArray();
    return { Success => 0, Error => 'QUEUE_WRITE_FAILED' } if !$ID;
    return { Success => 0, Error => 'IDEMPOTENCY_CONFLICT' } if $StoredPayload ne $PayloadJSON;
    return { Success => 1, Data => { OutboxID => 0 + $ID }, IdempotentReplay => $Inserted ? 0 : 1 };
}

sub Replay {
    my ( $Self, %Param ) = @_;
    return { Success => 0, Error => 'OUTBOX_ID_INVALID' }
        if ( $Param{OutboxID} // q{} ) !~ m{\A[1-9][0-9]*\z}smx;
    return { Success => 0, Error => 'ATTEMPT_COUNT_REQUIRED' }
        if ( $Param{ExpectedAttemptCount} // q{} ) !~ m{\A[1-9][0-9]*\z}smx;
    my $Decision = $Kernel::OM->Get('Kernel::System::CareOnCloud::TenantGuard')->DecisionGet(
        Subject => $Param{Subject}, Resource => { TenantID => $Param{TenantID} }, Action => 'tenant.manage',
    );
    return { Success => 0, Error => 'FORBIDDEN', Reason => $Decision->{Reason} } if !$Decision->{Allowed};
    my $At = $Self->_TimeNormalize( $Param{At} );
    return { Success => 0, Error => 'TIME_INVALID' } if !$At;

    my $DB = $Kernel::OM->Get('Kernel::System::DB');
    my $Handle = $DB->Connect();
    return { Success => 0, Error => 'TRANSACTION_CONNECTION_FAILED' } if !$Handle;
    my $OwnTransaction = $Handle->{AutoCommit} ? 1 : 0;
    my $Result;
    my $OK = eval {
        die "TRANSACTION_START_FAILED\n" if $OwnTransaction && !$DB->BeginWork();
        $DB->Prepare(
            SQL => 'SELECT commitment_id, status, attempt_count, replay_count, payload_json FROM careoncloud_escalation_outbox WHERE tenant_id = ? AND id = ?',
            Bind => [ \$Param{TenantID}, \$Param{OutboxID} ], Limit => 1,
        );
        my ( $CommitmentID, $Status, $Attempts, $ReplayCount, $PayloadJSON ) = $DB->FetchrowArray();
        if ( !$CommitmentID ) { $Result = { Success => 0, Error => 'NOT_FOUND' } }
        elsif ( $Status ne 'dead' ) { $Result = { Success => 0, Error => 'REPLAY_STATE_INVALID' } }
        elsif ( $Attempts != $Param{ExpectedAttemptCount} ) { $Result = { Success => 0, Error => 'VERSION_CONFLICT' } }
        else {
            my $Updated = $DB->Do(
                SQL => "UPDATE careoncloud_escalation_outbox SET status = 'retry', attempt_count = 0, replay_count = replay_count + 1, available_time = ?, processed_time = NULL, lease_token = '', lease_until = NULL, delivery_ref = '', response_code = '', last_error = '', change_time = current_timestamp WHERE tenant_id = ? AND id = ? AND status = 'dead' AND attempt_count = ?",
                Bind => [ \$At, \$Param{TenantID}, \$Param{OutboxID}, \$Param{ExpectedAttemptCount} ],
            );
            $DB->Prepare(
                SQL => 'SELECT status, attempt_count, replay_count FROM careoncloud_escalation_outbox WHERE tenant_id = ? AND id = ?',
                Bind => [ \$Param{TenantID}, \$Param{OutboxID} ], Limit => 1,
            );
            my ( $UpdatedStatus, $UpdatedAttempts, $UpdatedReplayCount ) = $DB->FetchrowArray();
            if ( !$Updated || ( $UpdatedStatus // q{} ) ne 'retry' || $UpdatedAttempts != 0 || $UpdatedReplayCount != $ReplayCount + 1 ) {
                $Result = { Success => 0, Error => 'VERSION_CONFLICT' };
            }
            else {
                my $ActorID = $Param{Subject}->{ID};
                my $ActorType = $ActorID =~ m{\Aintegration:}smx ? 'integration' : 'agent';
                my $Payload = $Kernel::OM->Get('Kernel::System::JSON')->Decode( Data => $PayloadJSON );
                $Payload = {} if ref $Payload ne 'HASH';
                my $CorrelationID = $CommitmentID
                    ? "commitment:$CommitmentID"
                    : 'audit:' . ( ref $Payload->{Event} eq 'HASH' ? $Payload->{Event}->{UUID} // $Param{OutboxID} : $Param{OutboxID} );
                my $Audit = $Kernel::OM->Get('Kernel::System::CareOnCloud::Audit')->Record(
                    TenantID => $Param{TenantID}, ActorType => $ActorType, ActorID => $ActorID,
                    Action => 'commitment.escalation_replayed', ObjectType => 'escalation_outbox', ObjectID => $Param{OutboxID},
                    CorrelationID => $CorrelationID, DedupeKey => "escalation:$Param{OutboxID}:replay:" . ( $ReplayCount + 1 ),
                    FromState => 'dead', ToState => 'retry', Outcome => 'success',
                    Details => { commitment_id => $CommitmentID, previous_attempt_count => $Attempts, replay_count => $ReplayCount + 1 },
                );
                $Result = $Audit->{Success}
                    ? { Success => 1, Data => { OutboxID => 0 + $Param{OutboxID}, Status => 'retry', AttemptCount => 0, ReplayCount => $ReplayCount + 1, AvailableTime => $At } }
                    : { Success => 0, Error => 'AUDIT_WRITE_FAILED' };
            }
        }
        if ($OwnTransaction) {
            die "TRANSACTION_COMMIT_FAILED\n" if $Result->{Success} && !$Handle->commit();
            die "TRANSACTION_ROLLBACK_FAILED\n" if !$Result->{Success} && !$DB->Rollback();
        }
        1;
    };
    if (!$OK) {
        eval { $DB->Rollback() } if $OwnTransaction && !$Handle->{AutoCommit};
        return { Success => 0, Error => 'TRANSACTION_FAILED' };
    }
    return $Result;
}

sub _ClaimedGet {
    my ( $Self, %Param ) = @_;
    my $DB = $Kernel::OM->Get('Kernel::System::DB');
    $DB->Prepare(
        SQL => "SELECT id, tenant_id, commitment_id, action_key, action_type, payload_json, attempt_count FROM careoncloud_escalation_outbox WHERE id = ? AND status = 'processing' AND lease_token = ?",
        Bind => [ \$Param{ID}, \$Param{Token} ], Limit => 1,
    );
    my @Row = $DB->FetchrowArray(); return if !@Row;
    my $Payload = $Kernel::OM->Get('Kernel::System::JSON')->Decode( Data => $Row[5] );
    return {
        ID => $Row[0], TenantID => $Row[1], CommitmentID => $Row[2], ActionKey => $Row[3], ActionType => $Row[4],
        Payload => ref $Payload eq 'HASH' ? $Payload : {}, AttemptCount => $Row[6],
        PayloadInvalid => ref $Payload ne 'HASH' || ( $Payload->{TenantID} // q{} ) ne $Row[1] ? 1 : 0,
    };
}

sub _Deliver {
    my ( $Self, %Param ) = @_;
    return { Success => 0, Error => 'PAYLOAD_TENANT_INVALID' } if $Param{Row}->{PayloadInvalid};
    my $Type = $Param{Row}->{ActionType};
    if ( ref $Param{Handlers} eq 'HASH' && ref $Param{Handlers}->{$Type} eq 'CODE' ) {
        return $Param{Handlers}->{$Type}->( $Param{Row} );
    }
    return $Self->_NotifyRole( $Param{Row} ) if $Type eq 'notify_role';
    return $Self->_Assign( $Param{Row} ) if $Type eq 'assignment';
    return $Self->_Webhook( $Param{Row} ) if $Type eq 'webhook';
    return { Success => 0, Error => 'ACTION_TYPE_UNSUPPORTED' };
}

sub _NotifyRole {
    my ( $Self, $Row ) = @_;
    my $Role = $Row->{Payload}->{Target} // q{};
    return { Success => 0, Error => 'ROLE_INVALID' } if $Role !~ m{\A[a-z][a-z0-9_]{0,29}\z}smx;
    my $DB = $Kernel::OM->Get('Kernel::System::DB');
    $DB->Prepare(
        SQL => "SELECT user_id FROM careoncloud_tenant_agent_role WHERE tenant_id = ? AND role_name = ? AND status = 'active' ORDER BY user_id",
        Bind => [ \$Row->{TenantID}, \$Role ],
    );
    my @Emails;
    while ( my ($UserID) = $DB->FetchrowArray() ) {
        my %User = $Kernel::OM->Get('Kernel::System::User')->GetUserData( UserID => $UserID, Valid => 1 );
        push @Emails, $User{UserEmail} if ( $User{UserEmail} // q{} ) =~ m{\A[^\s\@]+\@[^\s\@]+\z}smx;
    }
    return { Success => 0, Error => 'ROLE_HAS_NO_RECIPIENT' } if !@Emails;
    my $From = $Kernel::OM->Get('Kernel::Config')->Get('CareOnCloud::Commitment::NotificationFrom') // q{};
    return { Success => 0, Error => 'NOTIFICATION_FROM_INVALID' } if $From !~ m{\A[^\s\@]+\@[^\s\@]+\z}smx;
    my $Sent = $Kernel::OM->Get('Kernel::System::Email')->Send(
        From => $From, To => join( ', ', @Emails ), Charset => 'utf-8', MimeType => 'text/plain',
        Subject => "CareOnCloud commitment $Row->{Payload}->{Trigger}: $Row->{Payload}->{ObjectiveKey}",
        Body => "Tenant: $Row->{TenantID}\nRequest: $Row->{Payload}->{RequestID}\nObjective: $Row->{Payload}->{ObjectiveKey}\nDue: $Row->{Payload}->{DueTime}\n",
        CustomHeaders => { 'X-CareOnCloud-Escalation-ID' => $Row->{ID}, 'X-CareOnCloud-Tenant' => $Row->{TenantID} },
    );
    return $Sent ? { Success => 1, DeliveryRef => "mail:$Row->{ID}", ResponseCode => 'QUEUED' } : { Success => 0, Error => 'EMAIL_QUEUE_FAILED' };
}

sub _Assign {
    my ( $Self, $Row ) = @_;
    my $Group = $Row->{Payload}->{Target} // q{};
    return { Success => 0, Error => 'ASSIGNMENT_GROUP_INVALID' } if $Group !~ m{\A[a-z][a-z0-9_-]{0,63}\z}smx;
    my $DB = $Kernel::OM->Get('Kernel::System::DB');
    my $Empty = q{};
    $DB->Do(
        SQL => "UPDATE careoncloud_request_task SET assigned_group = ?, version = version + 1, change_time = current_timestamp, change_by = 'system:escalation-dispatcher' WHERE tenant_id = ? AND request_id = ? AND status IN ('pending','in_progress') AND assigned_group = ?",
        Bind => [ \$Group, \$Row->{TenantID}, \$Row->{Payload}->{RequestID}, \$Empty ],
    );
    $DB->Prepare(
        SQL => 'SELECT COUNT(*) FROM careoncloud_request_task WHERE tenant_id = ? AND request_id = ? AND assigned_group = ?',
        Bind => [ \$Row->{TenantID}, \$Row->{Payload}->{RequestID}, \$Group ],
    );
    my ($Count) = $DB->FetchrowArray();
    return $Count ? { Success => 1, DeliveryRef => "assignment:$Group", ResponseCode => 'ASSIGNED' } : { Success => 0, Error => 'ASSIGNABLE_TASK_NOT_FOUND' };
}

sub _Webhook {
    my ( $Self, $Row ) = @_;
    my $Key = $Row->{Payload}->{Target} // q{};
    return { Success => 0, Error => 'WEBHOOK_KEY_INVALID' } if $Key !~ m{\A[a-z][a-z0-9_-]{0,63}\z}smx;
    my $Config = $Kernel::OM->Get('Kernel::Config');
    my $Endpoints = $Self->_WebhookEndpointMap(
        $Config->Get('CareOnCloud::Commitment::WebhookEndpoints'),
    );
    my $Endpoint = $Endpoints->{$Key};
    return { Success => 0, Error => 'WEBHOOK_NOT_CONFIGURED' } if ref $Endpoint ne 'HASH';
    my $URI = URI->new( $Endpoint->{URL} // q{} );
    my %Allowed = map { lc($_) => 1 } @{ $Config->Get('CareOnCloud::Commitment::WebhookAllowedHosts') // [] };
    return { Success => 0, Error => 'WEBHOOK_URL_FORBIDDEN' }
        if lc( $URI->scheme // q{} ) ne 'https' || !$URI->host || !$Allowed{ lc $URI->host } || $URI->userinfo;
    my $Secret = $Endpoint->{Secret} // q{};
    return { Success => 0, Error => 'WEBHOOK_SECRET_INVALID' } if length $Secret < 32;
    my $JSON = $Kernel::OM->Get('Kernel::System::JSON')->Encode( Data => $Row->{Payload}, SortKeys => 1 );
    my $Timestamp = $Self->_TimeNormalize( $Row->{At} );
    return { Success => 0, Error => 'WEBHOOK_TIMESTAMP_INVALID' } if !$Timestamp;
    my $Signature = hmac_sha256_hex( "v1.$Timestamp.$Row->{ID}.$JSON", $Secret );
    my %Response = $Kernel::OM->Get('Kernel::System::WebUserAgent')->Request(
        URL => $URI->as_string, Type => 'POST', RawData => $JSON, NoLog => 1,
        Header => {
            'X-CareOnCloud-Signature-256' => "sha256=$Signature", 'X-CareOnCloud-Signature-Version' => 'v1',
            'X-CareOnCloud-Signature-Timestamp' => $Timestamp, 'X-CareOnCloud-Delivery-ID' => $Row->{ID},
            'X-CareOnCloud-Tenant' => $Row->{TenantID}, 'Content-Type' => 'application/json',
        },
    );
    return ( $Response{Status} // q{} ) =~ m{\A2[0-9][0-9]}smx
        ? { Success => 1, DeliveryRef => "webhook:$Row->{ID}", ResponseCode => $Response{Status} }
        : { Success => 0, Error => 'WEBHOOK_HTTP_' . ( $Response{Status} // '0' ) };
}

sub _WebhookEndpointMap {
    my ( $Self, $Configured ) = @_;
    my %Endpoints;
    if ( ref $Configured eq 'HASH' ) {
        for my $ConfigKey ( keys %{$Configured} ) {
            if ( ref $Configured->{$ConfigKey} eq 'HASH' ) {
                $Endpoints{$ConfigKey} = $Configured->{$ConfigKey};
            }
            elsif ( $ConfigKey =~ m{\A([a-z][a-z0-9_-]{0,63})::(URL|Secret)\z}smx ) {
                $Endpoints{$1}->{$2} = $Configured->{$ConfigKey};
            }
        }
    }
    return \%Endpoints;
}

sub _TimeNormalize {
    my ( $Self, $Time ) = @_;
    my $DT = defined $Time
        ? $Kernel::OM->Create( 'Kernel::System::DateTime', ObjectParams => { String => $Time, TimeZone => 'UTC' } )
        : $Kernel::OM->Create('Kernel::System::DateTime');
    return if !$DT; $DT->ToTimeZone( TimeZone => 'UTC' ); return $DT->ToString();
}

sub _AddSeconds {
    my ( $Self, %Param ) = @_;
    my $DT = $Kernel::OM->Create( 'Kernel::System::DateTime', ObjectParams => { String => $Param{Time}, TimeZone => 'UTC' } );
    return if !$DT || !$DT->Add( Seconds => $Param{Seconds} ); return $DT->ToString();
}

1;
