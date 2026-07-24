# --
# D724 ESM is an enterprise service management platform based on OTOBO.
# Copyright (C) 2026 Data Market Bilgi Hizmetleri A.S.
# SPDX-License-Identifier: GPL-3.0-only
# --

package Kernel::System::D724::Audit;

use v5.24;
use strict;
use warnings;
use Digest::SHA qw(sha256_hex);

our $VERSION = '0.1.0';
our @ObjectDependencies = (
    'Kernel::Config',
    'Kernel::System::D724::TenantDirectory',
    'Kernel::System::D724::TenantGuard',
    'Kernel::System::DB',
    'Kernel::System::JSON',
);

sub new { return bless {}, $_[0] }

sub Record {
    my ( $Self, %Param ) = @_;
    return $Self->_Error('AUDIT_DISABLED') if !$Self->_Enabled();
    return $Self->_Error('TENANT_INVALID') if ( $Param{TenantID} // q{} ) !~ m{\A[a-z0-9][a-z0-9_-]{1,127}\z}smx;
    return $Self->_Error('ACTOR_TYPE_INVALID') if ( $Param{ActorType} // q{} ) !~ m{\A(?:customer|agent|system|integration)\z}smx;
    for my $Spec (
        [ ActorID => 128, qr{\A[^\x00-\x1f]{1,128}\z} ], [ Action => 100, qr{\A[a-z][a-z0-9_.-]{1,99}\z} ],
        [ ObjectType => 50, qr{\A[a-z][a-z0-9_.-]{1,49}\z} ], [ ObjectID => 128, qr{\A[^\x00-\x1f]{1,128}\z} ],
    ) {
        return $Self->_Error( uc($Spec->[0]) . '_INVALID' ) if ( $Param{ $Spec->[0] } // q{} ) !~ $Spec->[2];
    }
    return $Self->_Error('OUTCOME_INVALID') if ( $Param{Outcome} // 'success' ) !~ m{\A(?:success|denied|failure)\z}smx;
    for my $Key (qw(CorrelationID FromState ToState)) {
        return $Self->_Error( uc($Key) . '_INVALID' ) if length( $Param{$Key} // q{} ) > 128 || ( $Param{$Key} // q{} ) =~ m{[\x00-\x1f]}smx;
    }
    my $Details = $Self->_DetailsNormalize( $Param{Details} // {} );
    return $Details if !$Details->{Success};
    my $At = $Self->_TimeNormalize( $Param{EventTime} );
    return $Self->_Error('TIME_INVALID') if !$At;
    my $SourceHash = q{};
    if ( length( $Param{SourceIP} // q{} ) ) {
        return $Self->_Error('SOURCE_IP_INVALID') if length $Param{SourceIP} > 64 || $Param{SourceIP} !~ m{\A[0-9a-fA-F:.]+\z}smx;
        my $Salt = $Kernel::OM->Get('Kernel::Config')->Get('D724::Audit::IPHashSalt') // q{};
        $SourceHash = sha256_hex( $Salt . q{|} . $Param{SourceIP} );
    }
    my $JSON = $Kernel::OM->Get('Kernel::System::JSON');
    my $DetailsJSON = $JSON->Encode( Data => $Details->{Data}, SortKeys => 1 );
    my $DB = $Kernel::OM->Get('Kernel::System::DB');
    my $OwnTransaction = $DB->{dbh}->{AutoCommit} ? 1 : 0;
    eval {
        $DB->BeginWork() if $OwnTransaction;
        my ( $Zero, $Version ) = ( '0' x 64, 1 );
        $DB->Do(
            SQL => 'INSERT IGNORE INTO d724_audit_head (tenant_id, last_sequence, last_hash, version, change_time) VALUES (?, 0, ?, ?, current_timestamp)',
            Bind => [ \$Param{TenantID}, \$Zero, \$Version ],
        );
        $DB->Prepare(
            SQL => 'SELECT last_sequence, last_hash FROM d724_audit_head WHERE tenant_id = ? FOR UPDATE',
            Bind => [ \$Param{TenantID} ],
        );
        my ( $LastSequence, $PreviousHash ) = $DB->FetchrowArray();
        die "HEAD_MISSING\n" if !defined $LastSequence;
        my $Sequence = $LastSequence + 1;
        my $UUID = sha256_hex( join q{|}, $Param{TenantID}, $Sequence, $At, $Param{ActorID}, $Param{Action}, $Param{ObjectType}, $Param{ObjectID}, $PreviousHash );
        my %Canonical = (
            tenant_id => $Param{TenantID}, sequence => $Sequence, event_uuid => $UUID, event_time => $At,
            actor_type => "$Param{ActorType}", actor_id => "$Param{ActorID}", action => "$Param{Action}",
            object_type => "$Param{ObjectType}", object_id => "$Param{ObjectID}", correlation_id => defined $Param{CorrelationID} ? "$Param{CorrelationID}" : q{},
            from_state => $Param{FromState} // q{}, to_state => $Param{ToState} // q{}, outcome => $Param{Outcome} // 'success',
            source_ip_hash => $SourceHash, details => $Details->{Data}, previous_hash => $PreviousHash,
        );
        my $EventHash = sha256_hex( $JSON->Encode( Data => \%Canonical, SortKeys => 1 ) );
        my @Values = (
            $Param{TenantID}, $Sequence, $UUID, $At, $Param{ActorType}, $Param{ActorID}, $Param{Action}, $Param{ObjectType}, $Param{ObjectID},
            $Param{CorrelationID} // q{}, $Param{FromState} // q{}, $Param{ToState} // q{}, $Param{Outcome} // 'success', $SourceHash,
            $DetailsJSON, $PreviousHash, $EventHash,
        );
        my @Bind = map { \$_ } @Values;
        die "EVENT_INSERT_FAILED\n" if !$DB->Do(
            SQL => 'INSERT INTO d724_audit_event (tenant_id, sequence_no, event_uuid, event_time, actor_type, actor_id, action_name, object_type, object_id, correlation_id, from_state, to_state, outcome, source_ip_hash, details_json, previous_hash, event_hash, create_time) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, current_timestamp)',
            Bind => \@Bind,
        );
        die "HEAD_UPDATE_FAILED\n" if !$DB->Do(
            SQL => 'UPDATE d724_audit_head SET last_sequence = ?, last_hash = ?, version = version + 1, change_time = current_timestamp WHERE tenant_id = ?',
            Bind => [ \$Sequence, \$EventHash, \$Param{TenantID} ],
        );
        $DB->{dbh}->commit() if $OwnTransaction;
        return { Success => 1, Data => { Sequence => $Sequence, EventUUID => $UUID, EventHash => $EventHash, PreviousHash => $PreviousHash } };
    } or do {
        my $Error = $@ || 'AUDIT_WRITE_FAILED'; eval { $DB->Rollback() } if $OwnTransaction;
        return $Self->_Error( $Error =~ m{(HEAD_MISSING|EVENT_INSERT_FAILED|HEAD_UPDATE_FAILED)} ? $1 : 'AUDIT_WRITE_FAILED' );
    };
}

sub List {
    my ( $Self, %Param ) = @_;
    my $Auth = $Self->_Authorize(%Param); return $Auth if !$Auth->{Success};
    my $After = $Param{AfterSequence} // 0;
    return $Self->_Error('CURSOR_INVALID') if $After !~ m{\A[0-9]+\z}smx;
    my $Limit = $Param{Limit} // $Kernel::OM->Get('Kernel::Config')->Get('D724::Audit::ExportLimit') // 500;
    return $Self->_Error('LIMIT_INVALID') if $Limit !~ m{\A[1-9][0-9]*\z}smx || $Limit > 1000;
    my $DB = $Kernel::OM->Get('Kernel::System::DB');
    my ( $Filter, @Values ) = ( q{}, $Param{TenantID}, $After );
    if ( defined $Param{ObjectType} || defined $Param{ObjectID} ) {
        return $Self->_Error('OBJECT_FILTER_INVALID') if ( $Param{ObjectType} // q{} ) !~ m{\A[a-z][a-z0-9_.-]{1,49}\z}smx || !length( $Param{ObjectID} // q{} ) || length $Param{ObjectID} > 128;
        $Filter = ' AND object_type = ? AND object_id = ?'; push @Values, @Param{qw(ObjectType ObjectID)};
    }
    my @Bind = map { \$_ } @Values;
    $DB->Prepare(
        SQL => "SELECT sequence_no, event_uuid, event_time, actor_type, actor_id, action_name, object_type, object_id, correlation_id, from_state, to_state, outcome, source_ip_hash, details_json, previous_hash, event_hash FROM d724_audit_event WHERE tenant_id = ? AND sequence_no > ?$Filter ORDER BY sequence_no",
        Bind => \@Bind, Limit => $Limit,
    );
    my @Data;
    while ( my @Row = $DB->FetchrowArray() ) { push @Data, $Self->_Row( TenantID => $Param{TenantID}, Row => \@Row ) }
    return { Success => 1, Data => \@Data, NextSequence => @Data ? $Data[-1]->{Sequence} : $After };
}

sub ExportNDJSON {
    my ( $Self, %Param ) = @_;
    my $Result = $Self->List(%Param); return $Result if !$Result->{Success};
    my $JSON = $Kernel::OM->Get('Kernel::System::JSON');
    my $Content = join q{}, map { $JSON->Encode( Data => $_, SortKeys => 1 ) . "\n" } @{ $Result->{Data} };
    return { %{$Result}, Content => $Content, ContentType => 'application/x-ndjson' };
}

sub Verify {
    my ( $Self, %Param ) = @_;
    my $Auth = $Self->_Authorize(%Param); return $Auth if !$Auth->{Success};
    my $DB = $Kernel::OM->Get('Kernel::System::DB');
    $DB->Prepare(
        SQL => 'SELECT sequence_no, event_uuid, event_time, actor_type, actor_id, action_name, object_type, object_id, correlation_id, from_state, to_state, outcome, source_ip_hash, details_json, previous_hash, event_hash FROM d724_audit_event WHERE tenant_id = ? ORDER BY sequence_no',
        Bind => [ \$Param{TenantID} ],
    );
    my ( $ExpectedSequence, $PreviousHash ) = ( 1, '0' x 64 );
    my $JSON = $Kernel::OM->Get('Kernel::System::JSON');
    while ( my @Row = $DB->FetchrowArray() ) {
        my $Data = $Self->_Row( TenantID => $Param{TenantID}, Row => \@Row );
        return { Success => 1, Valid => 0, Error => 'SEQUENCE_GAP', Sequence => $Data->{Sequence} } if $Data->{Sequence} != $ExpectedSequence;
        return { Success => 1, Valid => 0, Error => 'PREVIOUS_HASH_MISMATCH', Sequence => $Data->{Sequence} } if $Data->{PreviousHash} ne $PreviousHash;
        my %Canonical = (
            tenant_id => $Data->{TenantID}, sequence => $Data->{Sequence}, event_uuid => $Data->{EventUUID}, event_time => $Data->{EventTime},
            actor_type => $Data->{ActorType}, actor_id => $Data->{ActorID}, action => $Data->{Action}, object_type => $Data->{ObjectType}, object_id => $Data->{ObjectID},
            correlation_id => $Data->{CorrelationID}, from_state => $Data->{FromState}, to_state => $Data->{ToState}, outcome => $Data->{Outcome},
            source_ip_hash => $Data->{SourceIPHash}, details => $Data->{Details}, previous_hash => $Data->{PreviousHash},
        );
        my $Hash = sha256_hex( $JSON->Encode( Data => \%Canonical, SortKeys => 1 ) );
        return { Success => 1, Valid => 0, Error => 'EVENT_HASH_MISMATCH', Sequence => $Data->{Sequence} } if $Hash ne $Data->{EventHash};
        $PreviousHash = $Hash; $ExpectedSequence++;
    }
    $DB->Prepare( SQL => 'SELECT last_sequence, last_hash FROM d724_audit_head WHERE tenant_id = ?', Bind => [ \$Param{TenantID} ], Limit => 1 );
    my ( $HeadSequence, $HeadHash ) = $DB->FetchrowArray();
    $HeadSequence //= 0; $HeadHash //= '0' x 64;
    return { Success => 1, Valid => 0, Error => 'HEAD_MISMATCH' } if $HeadSequence != $ExpectedSequence - 1 || $HeadHash ne $PreviousHash;
    return { Success => 1, Valid => 1, Count => $HeadSequence, LastHash => $HeadHash };
}

sub _Authorize {
    my ( $Self, %Param ) = @_;
    return $Self->_Error('AUDIT_DISABLED') if !$Self->_Enabled();
    my $Subject = $Param{Subject};
    if ( ref $Subject ne 'HASH' && $Param{UserID} ) {
        my $Context = $Kernel::OM->Get('Kernel::System::D724::TenantDirectory')->ContextGet( UserID => $Param{UserID} );
        return $Context if !$Context->{Success}; $Subject = $Context->{Subject};
    }
    my $Decision = $Kernel::OM->Get('Kernel::System::D724::TenantGuard')->DecisionGet(
        Subject => $Subject, Resource => { TenantID => $Param{TenantID} }, Action => 'audit.read',
    );
    return $Self->_Error( 'FORBIDDEN', $Decision->{Reason} ) if !$Decision->{Allowed};
    return { Success => 1, Subject => $Subject };
}

sub _DetailsNormalize {
    my ( $Self, $Details ) = @_;
    return $Self->_Error('DETAILS_INVALID') if ref $Details ne 'HASH' || keys(%{$Details}) > 30;
    my %Data;
    for my $Key ( sort keys %{$Details} ) {
        return $Self->_Error('DETAILS_INVALID') if $Key !~ m{\A[a-z][a-z0-9_]{0,49}\z}smx;
        my $Value = $Details->{$Key}; return $Self->_Error('DETAILS_INVALID') if ref $Value || length( $Value // q{} ) > 1000 || ( $Value // q{} ) =~ m{[\x00-\x08\x0b\x0c\x0e-\x1f]}smx;
        $Data{$Key} = defined $Value ? "$Value" : q{};
    }
    return { Success => 1, Data => \%Data };
}

sub _Row {
    my ( $Self, %Param ) = @_; my @R = @{ $Param{Row} };
    my $Details = $Kernel::OM->Get('Kernel::System::JSON')->Decode( Data => $R[13] ); $Details = {} if ref $Details ne 'HASH';
    return { TenantID => $Param{TenantID}, Sequence => $R[0], EventUUID => $R[1], EventTime => $R[2], ActorType => $R[3], ActorID => $R[4], Action => $R[5], ObjectType => $R[6], ObjectID => $R[7], CorrelationID => $R[8], FromState => $R[9], ToState => $R[10], Outcome => $R[11], SourceIPHash => $R[12], Details => $Details, PreviousHash => $R[14], EventHash => $R[15] };
}

sub _TimeNormalize {
    my ( $Self, $Time ) = @_;
    my $DT = defined $Time ? $Kernel::OM->Create( 'Kernel::System::DateTime', ObjectParams => { String => $Time, TimeZone => 'UTC' } ) : $Kernel::OM->Create('Kernel::System::DateTime');
    return if !$DT; $DT->ToTimeZone( TimeZone => 'UTC' ); return $DT->ToString();
}
sub _Enabled { return $Kernel::OM->Get('Kernel::Config')->Get('D724::Audit::Enabled') ? 1 : 0 }
sub _Error { my ( $Self, $Error, $Reason ) = @_; return { Success => 0, Error => $Error, ( defined $Reason ? ( Reason => $Reason ) : () ) } }

1;
