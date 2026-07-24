# --
# D724 ESM is an enterprise service management platform based on OTOBO.
# Copyright (C) 2026 Data Market Bilgi Hizmetleri A.S.
# SPDX-License-Identifier: GPL-3.0-only
# --

package Kernel::System::D724::EscalationDispatcher;

use v5.24;
use strict;
use warnings;
use Digest::SHA qw(hmac_sha256_hex sha256_hex);
use URI ();

our $VERSION = '0.3.8';
our @ObjectDependencies = (
    'Kernel::Config',
    'Kernel::System::DB',
    'Kernel::System::Email',
    'Kernel::System::JSON',
    'Kernel::System::User',
    'Kernel::System::WebUserAgent',
);

sub new { return bless {}, $_[0] }

sub Dispatch {
    my ( $Self, %Param ) = @_;
    my $Config = $Kernel::OM->Get('Kernel::Config');
    return { Success => 0, Error => 'DISPATCH_DISABLED' } if !$Config->Get('D724::Commitment::EscalationDispatchEnabled');
    my $At = $Self->_TimeNormalize( $Param{At} );
    return { Success => 0, Error => 'TIME_INVALID' } if !$At;
    my $Limit = $Param{Limit} // $Config->Get('D724::Commitment::EscalationBatchSize') // 25;
    return { Success => 0, Error => 'LIMIT_INVALID' } if $Limit !~ m{\A[1-9][0-9]*\z}smx || $Limit > 100;
    my $Worker = $Param{WorkerID} // "dispatcher:$$";
    return { Success => 0, Error => 'WORKER_INVALID' } if $Worker !~ m{\A[a-zA-Z0-9_.:-]{1,64}\z}smx;
    my $DB = $Kernel::OM->Get('Kernel::System::DB');
    $DB->Do(
        SQL => "UPDATE d724_escalation_outbox SET status = 'retry', lease_token = '', lease_until = NULL, last_error = 'LEASE_EXPIRED', change_time = current_timestamp WHERE status = 'processing' AND lease_until < ?",
        Bind => [ \$At ],
    );
    $DB->Prepare(
        SQL => "SELECT id FROM d724_escalation_outbox WHERE status IN ('pending','retry') AND available_time <= ? ORDER BY available_time, id",
        Bind => [ \$At ], Limit => $Limit,
    );
    my @IDs; while ( my ($ID) = $DB->FetchrowArray() ) { push @IDs, $ID }
    my %Counts = ( Claimed => 0, Delivered => 0, Retried => 0, Dead => 0 );
    for my $ID (@IDs) {
        my $Token = sha256_hex( join q{:}, $Worker, $ID, $At, rand() );
        my $LeaseUntil = $Self->_AddSeconds( Time => $At, Seconds => 60 );
        $DB->Do(
            SQL => "UPDATE d724_escalation_outbox SET status = 'processing', lease_token = ?, lease_until = ?, attempt_count = attempt_count + 1, change_time = current_timestamp WHERE id = ? AND status IN ('pending','retry') AND available_time <= ?",
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
                SQL => "UPDATE d724_escalation_outbox SET status = 'delivered', processed_time = ?, lease_token = '', lease_until = NULL, delivery_ref = ?, response_code = ?, last_error = '', change_time = current_timestamp WHERE id = ? AND lease_token = ?",
                Bind => [ \$At, \$Ref, \$Code, \$ID, \$Token ],
            );
            $Counts{Delivered}++;
            next;
        }
        my $MaxAttempts = $Config->Get('D724::Commitment::EscalationMaxAttempts') // 5;
        my $Dead = $Row->{AttemptCount} >= $MaxAttempts ? 1 : 0;
        my $Status = $Dead ? 'dead' : 'retry';
        my $Delay = 60 * ( 2 ** ( $Row->{AttemptCount} - 1 ) );
        $Delay = 3600 if $Delay > 3600;
        my $Available = $Self->_AddSeconds( Time => $At, Seconds => $Delay );
        my $Error = substr( $Result->{Error} // 'DELIVERY_FAILED', 0, 2000 );
        $DB->Do(
            SQL => "UPDATE d724_escalation_outbox SET status = ?, available_time = ?, lease_token = '', lease_until = NULL, last_error = ?, response_code = ?, change_time = current_timestamp WHERE id = ? AND lease_token = ?",
            Bind => [ \$Status, \$Available, \$Error, \$Error, \$ID, \$Token ],
        );
        $Counts{ $Dead ? 'Dead' : 'Retried' }++;
    }
    return { Success => 1, Counts => \%Counts };
}

sub _ClaimedGet {
    my ( $Self, %Param ) = @_;
    my $DB = $Kernel::OM->Get('Kernel::System::DB');
    $DB->Prepare(
        SQL => "SELECT id, tenant_id, commitment_id, action_key, action_type, payload_json, attempt_count FROM d724_escalation_outbox WHERE id = ? AND status = 'processing' AND lease_token = ?",
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
        SQL => "SELECT user_id FROM d724_tenant_agent_role WHERE tenant_id = ? AND role_name = ? AND status = 'active' ORDER BY user_id",
        Bind => [ \$Row->{TenantID}, \$Role ],
    );
    my @Emails;
    while ( my ($UserID) = $DB->FetchrowArray() ) {
        my %User = $Kernel::OM->Get('Kernel::System::User')->GetUserData( UserID => $UserID, Valid => 1 );
        push @Emails, $User{UserEmail} if ( $User{UserEmail} // q{} ) =~ m{\A[^\s\@]+\@[^\s\@]+\z}smx;
    }
    return { Success => 0, Error => 'ROLE_HAS_NO_RECIPIENT' } if !@Emails;
    my $From = $Kernel::OM->Get('Kernel::Config')->Get('D724::Commitment::NotificationFrom') // q{};
    return { Success => 0, Error => 'NOTIFICATION_FROM_INVALID' } if $From !~ m{\A[^\s\@]+\@[^\s\@]+\z}smx;
    my $Sent = $Kernel::OM->Get('Kernel::System::Email')->Send(
        From => $From, To => join( ', ', @Emails ), Charset => 'utf-8', MimeType => 'text/plain',
        Subject => "D724 commitment $Row->{Payload}->{Trigger}: $Row->{Payload}->{ObjectiveKey}",
        Body => "Tenant: $Row->{TenantID}\nRequest: $Row->{Payload}->{RequestID}\nObjective: $Row->{Payload}->{ObjectiveKey}\nDue: $Row->{Payload}->{DueTime}\n",
        CustomHeaders => { 'X-D724-Escalation-ID' => $Row->{ID}, 'X-D724-Tenant' => $Row->{TenantID} },
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
        SQL => "UPDATE d724_request_task SET assigned_group = ?, version = version + 1, change_time = current_timestamp, change_by = 'system:escalation-dispatcher' WHERE tenant_id = ? AND request_id = ? AND status IN ('pending','in_progress') AND assigned_group = ?",
        Bind => [ \$Group, \$Row->{TenantID}, \$Row->{Payload}->{RequestID}, \$Empty ],
    );
    $DB->Prepare(
        SQL => 'SELECT COUNT(*) FROM d724_request_task WHERE tenant_id = ? AND request_id = ? AND assigned_group = ?',
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
    my $Endpoints = $Config->Get('D724::Commitment::WebhookEndpoints') // {};
    my $Endpoint = ref $Endpoints eq 'HASH' ? $Endpoints->{$Key} : undef;
    return { Success => 0, Error => 'WEBHOOK_NOT_CONFIGURED' } if ref $Endpoint ne 'HASH';
    my $URI = URI->new( $Endpoint->{URL} // q{} );
    my %Allowed = map { lc($_) => 1 } @{ $Config->Get('D724::Commitment::WebhookAllowedHosts') // [] };
    return { Success => 0, Error => 'WEBHOOK_URL_FORBIDDEN' }
        if lc( $URI->scheme // q{} ) ne 'https' || !$URI->host || !$Allowed{ lc $URI->host } || $URI->userinfo;
    my $Secret = $Endpoint->{Secret} // q{};
    return { Success => 0, Error => 'WEBHOOK_SECRET_INVALID' } if length $Secret < 32;
    my $JSON = $Kernel::OM->Get('Kernel::System::JSON')->Encode( Data => $Row->{Payload}, SortKeys => 1 );
    my $Signature = hmac_sha256_hex( $JSON, $Secret );
    my %Response = $Kernel::OM->Get('Kernel::System::WebUserAgent')->Request(
        URL => $URI->as_string, Type => 'POST', Data => [ payload => $JSON ], NoLog => 1,
        Header => { 'X-D724-Signature-256' => "sha256=$Signature", 'X-D724-Delivery-ID' => $Row->{ID} },
    );
    return ( $Response{Status} // q{} ) =~ m{\A2[0-9][0-9]}smx
        ? { Success => 1, DeliveryRef => "webhook:$Row->{ID}", ResponseCode => $Response{Status} }
        : { Success => 0, Error => 'WEBHOOK_HTTP_' . ( $Response{Status} // '0' ) };
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
