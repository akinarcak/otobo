# --
# D724 ESM is an enterprise service management platform based on OTOBO.
# Copyright (C) 2026 Data Market Bilgi Hizmetleri A.S.
# SPDX-License-Identifier: GPL-3.0-only
# --
package Kernel::System::D724::Webhook;

use v5.24;
use strict;
use warnings;

our $VERSION = '0.1.0';
our @ObjectDependencies = (
    'Kernel::Config',
    'Kernel::System::D724::Audit',
    'Kernel::System::D724::EscalationDispatcher',
    'Kernel::System::D724::TenantGuard',
    'Kernel::System::DB',
    'Kernel::System::JSON',
    'Kernel::System::Log',
);

sub new { return bless {}, $_[0] }

sub SubscriptionCreate {
    my ( $Self, %Param ) = @_;
    return $Self->_TransactionRun( Code => sub { return $Self->_SubscriptionCreate(%Param) } );
}

sub _SubscriptionCreate {
    my ( $Self, %Param ) = @_;
    return $Self->_Error('WEBHOOK_DISABLED') if !$Self->_Enabled();
    my $Auth = $Self->_Authorize(%Param); return $Auth if !$Auth->{Success};
    my $Valid = $Self->_SubscriptionValidate(%Param); return $Valid if !$Valid->{Success};
    my $DB = $Kernel::OM->Get('Kernel::System::DB');
    $DB->Prepare(
        SQL => 'SELECT id FROM d724_webhook_subscription WHERE tenant_id = ? AND key_name = ?',
        Bind => [ \$Param{TenantID}, \$Param{Key} ], Limit => 1,
    );
    return $Self->_Error('KEY_EXISTS') if $DB->FetchrowArray();
    my $Head = $Self->_AuditHead( TenantID => $Param{TenantID} );
    my $Cursor = defined $Param{StartSequence} ? $Param{StartSequence} : $Head;
    return $Self->_Error('CURSOR_INVALID')
        if $Cursor !~ m{\A[0-9]+\z}smx || $Cursor > $Head;
    my $PatternsJSON = $Kernel::OM->Get('Kernel::System::JSON')->Encode( Data => $Param{EventPatterns}, SortKeys => 1 );
    my $Actor = $Auth->{Subject}->{ID};
    my @Values = (
        $Param{TenantID}, $Param{Key}, $Param{Name}, $Param{EndpointKey}, $PatternsJSON,
        $Param{Status} // 'active', $Cursor, $Actor, $Actor,
    );
    my @Bind = map { \$_ } @Values;
    return $Self->_Error('DATABASE_ERROR') if !$DB->Do(
        SQL => 'INSERT INTO d724_webhook_subscription (tenant_id, key_name, name, endpoint_key, event_patterns_json, status, cursor_sequence, version, create_time, create_by, change_time, change_by) VALUES (?, ?, ?, ?, ?, ?, ?, 1, current_timestamp, ?, current_timestamp, ?)',
        Bind => \@Bind,
    );
    my $Data = $Self->_SubscriptionRowGet( TenantID => $Param{TenantID}, Key => $Param{Key} );
    return $Self->_Error('DATABASE_ERROR') if !$Data;
    my $Audit = $Self->_Audit(
        %Param, Subject => $Auth->{Subject}, Action => 'webhook.subscription_created',
        ObjectID => $Data->{SubscriptionID}, DedupeKey => "webhook-subscription:$Data->{SubscriptionID}:created",
        FromState => q{}, ToState => $Data->{Status},
        Details => { key => $Data->{Key}, endpoint_key => $Data->{EndpointKey}, cursor_sequence => $Cursor },
    );
    return $Audit if !$Audit->{Success};
    return { Success => 1, Data => $Data };
}

sub SubscriptionUpdate {
    my ( $Self, %Param ) = @_;
    return $Self->_TransactionRun( Code => sub { return $Self->_SubscriptionUpdate(%Param) } );
}

sub _SubscriptionUpdate {
    my ( $Self, %Param ) = @_;
    return $Self->_Error('WEBHOOK_DISABLED') if !$Self->_Enabled();
    return $Self->_Error('SUBSCRIPTION_ID_INVALID') if !$Self->_PositiveInteger( $Param{SubscriptionID} );
    return $Self->_Error('VERSION_REQUIRED') if !$Self->_PositiveInteger( $Param{ExpectedVersion} );
    my $Auth = $Self->_Authorize(%Param); return $Auth if !$Auth->{Success};
    my $Current = $Self->_SubscriptionRowGet( TenantID => $Param{TenantID}, SubscriptionID => $Param{SubscriptionID} );
    return $Self->_Error('NOT_FOUND') if !$Current;
    return $Self->_Error('VERSION_CONFLICT') if $Current->{Version} != $Param{ExpectedVersion};
    $Param{Name}          //= $Current->{Name};
    $Param{EndpointKey}   //= $Current->{EndpointKey};
    $Param{EventPatterns} //= $Current->{EventPatterns};
    $Param{Status}        //= $Current->{Status};
    $Param{Key} = $Current->{Key};
    my $Valid = $Self->_SubscriptionValidate(%Param); return $Valid if !$Valid->{Success};
    my $PatternsJSON = $Kernel::OM->Get('Kernel::System::JSON')->Encode( Data => $Param{EventPatterns}, SortKeys => 1 );
    my $Actor = $Auth->{Subject}->{ID};
    my @Values = (
        $Param{Name}, $Param{EndpointKey}, $PatternsJSON, $Param{Status}, $Actor,
        $Param{TenantID}, $Param{SubscriptionID}, $Param{ExpectedVersion},
    );
    my @Bind = map { \$_ } @Values;
    return $Self->_Error('DATABASE_ERROR') if !$Kernel::OM->Get('Kernel::System::DB')->Do(
        SQL => 'UPDATE d724_webhook_subscription SET name = ?, endpoint_key = ?, event_patterns_json = ?, status = ?, version = version + 1, change_time = current_timestamp, change_by = ? WHERE tenant_id = ? AND id = ? AND version = ?',
        Bind => \@Bind,
    );
    my $Data = $Self->_SubscriptionRowGet( TenantID => $Param{TenantID}, SubscriptionID => $Param{SubscriptionID} );
    return $Self->_Error('VERSION_CONFLICT') if !$Data || $Data->{Version} != $Param{ExpectedVersion} + 1;
    my $Audit = $Self->_Audit(
        %Param, Subject => $Auth->{Subject}, Action => 'webhook.subscription_updated',
        ObjectID => $Data->{SubscriptionID}, DedupeKey => "webhook-subscription:$Data->{SubscriptionID}:version:$Data->{Version}",
        FromState => $Current->{Status}, ToState => $Data->{Status},
        Details => { key => $Data->{Key}, endpoint_key => $Data->{EndpointKey}, version => $Data->{Version} },
    );
    return $Audit if !$Audit->{Success};
    return { Success => 1, Data => $Data };
}

sub SubscriptionGet {
    my ( $Self, %Param ) = @_;
    return $Self->_Error('WEBHOOK_DISABLED') if !$Self->_Enabled();
    return $Self->_Error('SUBSCRIPTION_ID_INVALID') if !$Self->_PositiveInteger( $Param{SubscriptionID} );
    my $Auth = $Self->_Authorize(%Param); return $Auth if !$Auth->{Success};
    my $Data = $Self->_SubscriptionRowGet( TenantID => $Param{TenantID}, SubscriptionID => $Param{SubscriptionID} );
    return $Data ? { Success => 1, Data => $Data } : $Self->_Error('NOT_FOUND');
}

sub SubscriptionList {
    my ( $Self, %Param ) = @_;
    return $Self->_Error('WEBHOOK_DISABLED') if !$Self->_Enabled();
    my $Auth = $Self->_Authorize(%Param); return $Auth if !$Auth->{Success};
    my $DB = $Kernel::OM->Get('Kernel::System::DB');
    $DB->Prepare(
        SQL => 'SELECT id FROM d724_webhook_subscription WHERE tenant_id = ? ORDER BY id',
        Bind => [ \$Param{TenantID} ], Limit => 500,
    );
    my @IDs;
    while ( my ($ID) = $DB->FetchrowArray() ) { push @IDs, $ID }
    my @Data = map {
        $Self->_SubscriptionRowGet( TenantID => $Param{TenantID}, SubscriptionID => $_ )
    } @IDs;
    return { Success => 1, Data => \@Data };
}

sub Scan {
    my ( $Self, %Param ) = @_;
    return $Self->_Error('WEBHOOK_DISABLED') if !$Self->_Enabled();
    my $Limit = $Param{Limit} // $Kernel::OM->Get('Kernel::Config')->Get('D724::Webhook::ScanBatchSize') // 100;
    return $Self->_Error('LIMIT_INVALID') if $Limit !~ m{\A[1-9][0-9]*\z}smx || $Limit > 500;
    my $DB = $Kernel::OM->Get('Kernel::System::DB');
    $DB->Prepare( SQL => "SELECT id, tenant_id FROM d724_webhook_subscription WHERE status = 'active' ORDER BY tenant_id, id", Limit => 5000 );
    my @Subscriptions;
    while ( my @Row = $DB->FetchrowArray() ) { push @Subscriptions, \@Row }
    my %Counts = ( Subscriptions => scalar @Subscriptions, Scanned => 0, Matched => 0, Queued => 0, Replayed => 0, Errors => 0 );
    for my $Row (@Subscriptions) {
        my $Result = $Self->_ScanSubscription( SubscriptionID => $Row->[0], TenantID => $Row->[1], Limit => $Limit );
        if ( !$Result->{Success} ) { $Counts{Errors}++; next }
        $Counts{$_} += $Result->{Counts}->{$_} for qw(Scanned Matched Queued Replayed);
    }
    return { Success => $Counts{Errors} ? 0 : 1, Counts => \%Counts };
}

sub _ScanSubscription {
    my ( $Self, %Param ) = @_;
    my $Subscription = $Self->_SubscriptionRowGet(%Param);
    return $Self->_Error('NOT_FOUND') if !$Subscription || $Subscription->{Status} ne 'active';
    my $DB = $Kernel::OM->Get('Kernel::System::DB');
    my $Cursor = $Subscription->{CursorSequence};
    $DB->Prepare(
        SQL => 'SELECT sequence_no, event_uuid, event_time, actor_type, actor_id, action_name, object_type, object_id, correlation_id, from_state, to_state, outcome, details_json, event_hash FROM d724_audit_event WHERE tenant_id = ? AND sequence_no > ? ORDER BY sequence_no',
        Bind => [ \$Param{TenantID}, \$Cursor ], Limit => $Param{Limit},
    );
    my @Events;
    while ( my @Row = $DB->FetchrowArray() ) { push @Events, \@Row }
    my %Counts = ( Scanned => 0, Matched => 0, Queued => 0, Replayed => 0 );
    for my $Event (@Events) {
        my $Result = $Self->_TransactionRun( Code => sub {
            return $Self->_ScanEvent( Subscription => $Subscription, Event => $Event );
        } );
        return $Result if !$Result->{Success};
        $Counts{Scanned}++;
        if ( $Result->{Matched} ) {
            $Counts{Matched}++;
            $Counts{ $Result->{IdempotentReplay} ? 'Replayed' : 'Queued' }++;
        }
        $Subscription->{CursorSequence} = $Event->[0];
    }
    return { Success => 1, Counts => \%Counts };
}

sub _ScanEvent {
    my ( $Self, %Param ) = @_;
    my $Subscription = $Param{Subscription};
    my $Event = $Param{Event};
    my $Sequence = $Event->[0];
    my $Matched = $Self->_EventMatches( Patterns => $Subscription->{EventPatterns}, Action => $Event->[5] );
    my $Queue;
    if ($Matched) {
        my $Details = $Kernel::OM->Get('Kernel::System::JSON')->Decode( Data => $Event->[12] );
        $Details = {} if ref $Details ne 'HASH';
        my $Payload = {
            SchemaVersion => 1, TenantID => $Subscription->{TenantID},
            SubscriptionID => 0 + $Subscription->{SubscriptionID}, SubscriptionKey => $Subscription->{Key},
            Event => {
                Sequence => 0 + $Sequence, UUID => $Event->[1], Time => $Event->[2],
                ActorType => $Event->[3], ActorID => $Event->[4], Action => $Event->[5],
                ObjectType => $Event->[6], ObjectID => $Event->[7], CorrelationID => $Event->[8],
                FromState => $Event->[9], ToState => $Event->[10], Outcome => $Event->[11],
                Details => $Details, Hash => $Event->[13],
            },
        };
        $Queue = $Kernel::OM->Get('Kernel::System::D724::EscalationDispatcher')->QueueWebhook(
            TenantID => $Subscription->{TenantID}, SourceSequence => $Sequence,
            ActionKey => 'webhooksub' . $Subscription->{SubscriptionID}, EndpointKey => $Subscription->{EndpointKey},
            Payload => $Payload, At => $Event->[2],
        );
        return $Queue if !$Queue->{Success};
    }
    my $DB = $Kernel::OM->Get('Kernel::System::DB');
    $DB->Do(
        SQL => 'UPDATE d724_webhook_subscription SET cursor_sequence = ?, change_time = current_timestamp WHERE tenant_id = ? AND id = ? AND cursor_sequence < ?',
        Bind => [ \$Sequence, \$Subscription->{TenantID}, \$Subscription->{SubscriptionID}, \$Sequence ],
    );
    my $Current = $Self->_SubscriptionRowGet( TenantID => $Subscription->{TenantID}, SubscriptionID => $Subscription->{SubscriptionID} );
    return $Self->_Error('CURSOR_UPDATE_FAILED') if !$Current || $Current->{CursorSequence} < $Sequence;
    return { Success => 1, Matched => $Matched ? 1 : 0, IdempotentReplay => $Queue && $Queue->{IdempotentReplay} ? 1 : 0 };
}

sub _SubscriptionValidate {
    my ( $Self, %Param ) = @_;
    return $Self->_Error('KEY_INVALID') if ( $Param{Key} // q{} ) !~ m{\A[a-z][a-z0-9_-]{0,63}\z}smx;
    return $Self->_Error('NAME_INVALID') if !length( $Param{Name} // q{} ) || length $Param{Name} > 200;
    return $Self->_Error('ENDPOINT_KEY_INVALID') if ( $Param{EndpointKey} // q{} ) !~ m{\A[a-z][a-z0-9_-]{0,63}\z}smx;
    my $Configured = $Kernel::OM->Get('Kernel::Config')->Get('D724::Commitment::WebhookEndpoints');
    my $Endpoints = $Self->_WebhookEndpointMap($Configured);
    return $Self->_Error('ENDPOINT_NOT_CONFIGURED') if ref $Endpoints->{ $Param{EndpointKey} } ne 'HASH';
    return $Self->_Error('EVENT_PATTERNS_INVALID') if ref $Param{EventPatterns} ne 'ARRAY' || !@{ $Param{EventPatterns} } || @{ $Param{EventPatterns} } > 20;
    my %Seen;
    for my $Pattern ( @{ $Param{EventPatterns} } ) {
        return $Self->_Error('EVENT_PATTERN_INVALID')
            if $Pattern !~ m{\A[a-z][a-z0-9_.-]{0,98}(?:\.\*)?\z}smx || $Seen{$Pattern}++;
    }
    return $Self->_Error('STATUS_INVALID') if ( $Param{Status} // 'active' ) !~ m{\A(?:active|inactive)\z}smx;
    return { Success => 1 };
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

sub _EventMatches {
    my ( $Self, %Param ) = @_;
    for my $Pattern ( @{ $Param{Patterns} } ) {
        return 1 if $Pattern eq $Param{Action};
        if ( $Pattern =~ m{\A(.+)\.\*\z}smx ) {
            return 1 if index( $Param{Action}, "$1." ) == 0;
        }
    }
    return 0;
}

sub _SubscriptionRowGet {
    my ( $Self, %Param ) = @_;
    my ( $Where, $Value ) = defined $Param{SubscriptionID} ? ( 'id', $Param{SubscriptionID} ) : ( 'key_name', $Param{Key} );
    my $DB = $Kernel::OM->Get('Kernel::System::DB');
    $DB->Prepare(
        SQL => "SELECT id, tenant_id, key_name, name, endpoint_key, event_patterns_json, status, cursor_sequence, version, create_time, create_by, change_time, change_by FROM d724_webhook_subscription WHERE tenant_id = ? AND $Where = ?",
        Bind => [ \$Param{TenantID}, \$Value ], Limit => 1,
    );
    my @Row = $DB->FetchrowArray(); return if !@Row;
    my $Patterns = $Kernel::OM->Get('Kernel::System::JSON')->Decode( Data => $Row[5] );
    return {
        SubscriptionID => $Row[0], TenantID => $Row[1], Key => $Row[2], Name => $Row[3], EndpointKey => $Row[4],
        EventPatterns => ref $Patterns eq 'ARRAY' ? $Patterns : [], Status => $Row[6], CursorSequence => $Row[7], Version => $Row[8],
        CreateTime => $Row[9], CreateBy => $Row[10], ChangeTime => $Row[11], ChangeBy => $Row[12],
    };
}

sub _AuditHead {
    my ( $Self, %Param ) = @_;
    $Kernel::OM->Get('Kernel::System::DB')->Prepare(
        SQL => 'SELECT last_sequence FROM d724_audit_head WHERE tenant_id = ?', Bind => [ \$Param{TenantID} ], Limit => 1,
    );
    my ($Sequence) = $Kernel::OM->Get('Kernel::System::DB')->FetchrowArray();
    return $Sequence // 0;
}

sub _Authorize {
    my ( $Self, %Param ) = @_;
    my $Decision = $Kernel::OM->Get('Kernel::System::D724::TenantGuard')->DecisionGet(
        Subject => $Param{Subject}, Resource => { TenantID => $Param{TenantID} }, Action => 'tenant.manage',
    );
    return $Self->_Error( 'FORBIDDEN', $Decision->{Reason} ) if !$Decision->{Allowed};
    return { Success => 1, Subject => $Param{Subject} };
}

sub _Audit {
    my ( $Self, %Param ) = @_;
    my $ActorID = $Param{Subject}->{ID};
    my $ActorType = $ActorID =~ m{\Aintegration:}smx ? 'integration' : 'agent';
    my $Result = $Kernel::OM->Get('Kernel::System::D724::Audit')->Record(
        TenantID => $Param{TenantID}, ActorType => $ActorType, ActorID => $ActorID,
        Action => $Param{Action}, ObjectType => 'webhook_subscription', ObjectID => $Param{ObjectID},
        CorrelationID => "webhook-subscription:$Param{ObjectID}", DedupeKey => $Param{DedupeKey},
        FromState => $Param{FromState}, ToState => $Param{ToState}, Outcome => 'success', Details => $Param{Details},
    );
    return $Result->{Success} ? { Success => 1 } : $Self->_Error('AUDIT_WRITE_FAILED');
}

sub _TransactionRun {
    my ( $Self, %Param ) = @_;
    return $Self->_Error('TRANSACTION_CODE_INVALID') if ref $Param{Code} ne 'CODE';
    my $DB = $Kernel::OM->Get('Kernel::System::DB');
    my $Handle = $DB->Connect(); return $Self->_Error('TRANSACTION_CONNECTION_FAILED') if !$Handle;
    return $Param{Code}->() if !$Handle->{AutoCommit};
    my $Result;
    my $OK = eval {
        die "TRANSACTION_START_FAILED\n" if !$DB->BeginWork();
        $Result = $Param{Code}->();
        die "TRANSACTION_RESULT_INVALID\n" if ref $Result ne 'HASH' || !exists $Result->{Success};
        die "TRANSACTION_COMMIT_FAILED\n" if $Result->{Success} && !$Handle->commit();
        die "TRANSACTION_ROLLBACK_FAILED\n" if !$Result->{Success} && !$DB->Rollback();
        1;
    };
    if (!$OK) {
        eval { $DB->Rollback() } if !$Handle->{AutoCommit};
        $Kernel::OM->Get('Kernel::System::Log')->Log( Priority => 'error', Message => "D724 webhook transaction failed: " . ( $@ || 'unknown' ) );
        return $Self->_Error('TRANSACTION_FAILED');
    }
    return $Result;
}

sub _Enabled { return $Kernel::OM->Get('Kernel::Config')->Get('D724::Webhook::Enabled') ? 1 : 0 }
sub _PositiveInteger { return defined $_[1] && $_[1] =~ m{\A[1-9][0-9]*\z}smx ? 1 : 0 }
sub _Error { my ( $Self, $Code, $Reason ) = @_; return { Success => 0, Error => $Code, ( defined $Reason ? ( Reason => $Reason ) : () ) } }

1;
