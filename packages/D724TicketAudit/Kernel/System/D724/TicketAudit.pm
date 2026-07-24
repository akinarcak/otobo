# --
# Copyright (C) 2026 Data Market Bilgi Hizmetleri A.S.
# SPDX-License-Identifier: GPL-3.0-only
# --
package Kernel::System::D724::TicketAudit;

use v5.24;
use strict;
use warnings;

our $VERSION = '0.1.0';
our @ObjectDependencies = (
    'Kernel::Config',
    'Kernel::System::D724::Audit',
    'Kernel::System::D724::TenantDirectory',
    'Kernel::System::DB',
    'Kernel::System::Log',
);

sub new { return bless {}, $_[0] }

sub TicketCreateRun {
    my ( $Self, %Param ) = @_;
    return $Param{Original}->( $Param{TicketObject}, %{ $Param{Param} } ) if !$Self->_Enabled();
    my $Call = $Param{Param};
    my $TenantID = $Call->{CustomerNo} // $Call->{CustomerID} // q{};
    if ( !$Self->_TenantActive($TenantID) ) {
        $Self->_Log("D724 ticket create rejected: tenant missing or inactive ($TenantID)");
        return;
    }
    my $Result = $Self->_TransactionRun(
        OnFailure => sub { $Self->_CacheClear( TicketObject => $Param{TicketObject} ) },
        Code => sub {
            local $Param{TicketObject}->{D724TicketAuditSuppress} = 1;
            my $TicketID = $Param{Original}->( $Param{TicketObject}, %{$Call} );
            return $Self->_Error('TICKET_CREATE_FAILED') if !$TicketID;
            my $UserID = $Call->{UserID};
            my @Values = ( $TicketID, $TenantID, $UserID, $UserID );
            my @Bind = map { \$_ } @Values;
            return $Self->_Error('TICKET_SCOPE_WRITE_FAILED') if !$Kernel::OM->Get('Kernel::System::DB')->Do(
                SQL => "INSERT INTO d724_ticket_scope (ticket_id, tenant_id, version, status, create_time, create_by, change_time, change_by) VALUES (?, ?, 1, 'active', current_timestamp, ?, current_timestamp, ?)",
                Bind => \@Bind,
            );
            my %Ticket = $Param{TicketObject}->TicketGet( TicketID => $TicketID, DynamicFields => 0, UserID => $UserID );
            my $Audit = $Self->_AuditRecord(
                TenantID => $TenantID, TicketID => $TicketID, UserID => $UserID,
                Action => 'ticket.created', Version => 1, FromState => q{}, ToState => $Ticket{State} // q{},
                Details => { ticket_number => $Ticket{TicketNumber} // q{}, title => $Ticket{Title} // q{}, queue => $Ticket{Queue} // q{} },
            );
            return $Self->_Error('AUDIT_WRITE_FAILED') if !$Audit->{Success};
            return { Success => 1, Value => $TicketID };
        },
    );
    return $Result->{Success} ? $Result->{Value} : undef;
}

sub MutationRun {
    my ( $Self, %Param ) = @_;
    my $Call = $Param{Param};
    return $Param{Original}->( $Param{TicketObject}, %{$Call} ) if !$Self->_Enabled();
    my $TicketID = $Call->{TicketID};
    return if !$TicketID;
    my $Result = $Self->_TransactionRun(
        OnFailure => sub { $Self->_CacheClear( TicketObject => $Param{TicketObject}, TicketID => $TicketID ) },
        Code => sub {
            my $Scope = $Self->_ScopeLock( TicketID => $TicketID );
            return $Self->_Error('TICKET_SCOPE_MISSING') if !$Scope;
            if ( $Param{Field} eq 'CustomerID' ) {
                my $RequestedTenant = $Call->{No} // $Call->{CustomerID} // q{};
                return $Self->_Error('TENANT_CHANGE_FORBIDDEN') if length $RequestedTenant && $RequestedTenant ne $Scope->{TenantID};
            }
            my %Before = $Param{TicketObject}->TicketGet( TicketID => $TicketID, DynamicFields => 0, UserID => $Call->{UserID} );
            local $Param{TicketObject}->{D724TicketAuditSuppress} = 1;
            my $Value = $Param{Original}->( $Param{TicketObject}, %{$Call} );
            return $Self->_Error('TICKET_MUTATION_FAILED') if !$Value;
            my %After = $Param{TicketObject}->TicketGet( TicketID => $TicketID, DynamicFields => 0, UserID => $Call->{UserID} );
            my $From = defined $Before{ $Param{Field} } ? "$Before{$Param{Field}}" : q{};
            my $To   = defined $After{ $Param{Field} }  ? "$After{$Param{Field}}"  : q{};
            return { Success => 1, Value => $Value } if $From eq $To;
            my $Version = $Scope->{Version} + 1;
            my @Values = ( $Call->{UserID}, $TicketID, $Scope->{Version} );
            my @Bind = map { \$_ } @Values;
            return $Self->_Error('VERSION_CONFLICT') if !$Kernel::OM->Get('Kernel::System::DB')->Do(
                SQL => 'UPDATE d724_ticket_scope SET version = version + 1, change_time = current_timestamp, change_by = ? WHERE ticket_id = ? AND version = ?', Bind => \@Bind,
            );
            my $Audit = $Self->_AuditRecord(
                TenantID => $Scope->{TenantID}, TicketID => $TicketID, UserID => $Call->{UserID},
                Action => $Param{Action}, Version => $Version, FromState => $From, ToState => $To,
                Details => { field => lc $Param{Field}, ticket_number => $After{TicketNumber} // q{}, version => $Version },
            );
            return $Self->_Error('AUDIT_WRITE_FAILED') if !$Audit->{Success};
            return { Success => 1, Value => $Value };
        },
    );
    return $Result->{Success} ? $Result->{Value} : undef;
}

sub ScopeGet {
    my ( $Self, %Param ) = @_;
    my $TicketID = $Param{TicketID};
    $Kernel::OM->Get('Kernel::System::DB')->Prepare(
        SQL => 'SELECT tenant_id, version, status FROM d724_ticket_scope WHERE ticket_id = ?', Bind => [ \$TicketID ], Limit => 1,
    );
    my @Row = $Kernel::OM->Get('Kernel::System::DB')->FetchrowArray();
    return if !defined $Row[0];
    return { TicketID => $TicketID, TenantID => $Row[0], Version => $Row[1], Status => $Row[2] };
}

sub _ScopeLock {
    my ( $Self, %Param ) = @_;
    my $TicketID = $Param{TicketID};
    $Kernel::OM->Get('Kernel::System::DB')->Prepare(
        SQL => 'SELECT tenant_id, version, status FROM d724_ticket_scope WHERE ticket_id = ? FOR UPDATE', Bind => [ \$TicketID ], Limit => 1,
    );
    my @Row = $Kernel::OM->Get('Kernel::System::DB')->FetchrowArray();
    return if !defined $Row[0];
    return { TicketID => $TicketID, TenantID => $Row[0], Version => $Row[1], Status => $Row[2] };
}

sub _TenantActive {
    my ( $Self, $TenantID ) = @_;
    return if ( $TenantID // q{} ) !~ m{\A[a-z0-9][a-z0-9_-]{1,127}\z}smx;
    $Kernel::OM->Get('Kernel::System::DB')->Prepare(
        SQL => "SELECT id FROM d724_tenant WHERE key_name = ? AND status = 'active'", Bind => [ \$TenantID ], Limit => 1,
    );
    my ($ID) = $Kernel::OM->Get('Kernel::System::DB')->FetchrowArray();
    return $ID;
}

sub _AuditRecord {
    my ( $Self, %Param ) = @_;
    my ( $ActorType, $ActorID ) = $Self->_Actor( UserID => $Param{UserID}, TenantID => $Param{TenantID} );
    return $Kernel::OM->Get('Kernel::System::D724::Audit')->Record(
        TenantID => $Param{TenantID}, ActorType => $ActorType, ActorID => $ActorID,
        Action => $Param{Action}, ObjectType => 'ticket', ObjectID => "$Param{TicketID}",
        CorrelationID => "ticket:$Param{TicketID}", DedupeKey => "ticket:$Param{TicketID}:version:$Param{Version}",
        FromState => $Param{FromState}, ToState => $Param{ToState}, Outcome => 'success', Details => $Param{Details},
    );
}

sub _Actor {
    my ( $Self, %Param ) = @_;
    my $Context = $Kernel::OM->Get('Kernel::System::D724::TenantDirectory')->ContextGet( UserID => $Param{UserID} );
    if ( $Context->{Success} && grep { $_ eq $Param{TenantID} } @{ $Context->{Subject}->{TenantIDs} // [] } ) {
        return ( 'agent', "agent:$Param{UserID}" );
    }
    return ( 'system', "otobo-user:$Param{UserID}" );
}

sub _TransactionRun {
    my ( $Self, %Param ) = @_;
    my $DB = $Kernel::OM->Get('Kernel::System::DB');
    my $Handle = $DB->Connect();
    return $Self->_Error('TRANSACTION_CONNECTION_FAILED') if !$Handle;
    return $Param{Code}->() if !$Handle->{AutoCommit};
    my $Result;
    my $OK = eval {
        die "TRANSACTION_START_FAILED\n" if !$DB->BeginWork();
        $Result = $Param{Code}->();
        die "TRANSACTION_RESULT_INVALID\n" if ref $Result ne 'HASH' || !exists $Result->{Success};
        if ( $Result->{Success} ) { die "TRANSACTION_COMMIT_FAILED\n" if !$Handle->commit() }
        else { die "TRANSACTION_ROLLBACK_FAILED\n" if !$DB->Rollback() }
        1;
    };
    if ( !$OK ) {
        my $Failure = $@ || 'TRANSACTION_FAILED';
        eval { $DB->Rollback() } if !$Handle->{AutoCommit};
        $Self->_Log("D724 ticket audit transaction failed: $Failure");
        $Param{OnFailure}->() if ref $Param{OnFailure} eq 'CODE';
        return $Self->_Error('TRANSACTION_FAILED');
    }
    if ( !$Result->{Success} ) {
        $Self->_Log("D724 ticket audit mutation rejected: $Result->{Error}");
        $Param{OnFailure}->() if ref $Param{OnFailure} eq 'CODE';
    }
    return $Result;
}

sub _CacheClear {
    my ( $Self, %Param ) = @_;
    if ( $Param{TicketID} ) { eval { $Param{TicketObject}->_TicketCacheClear( TicketID => $Param{TicketID} ) } }
    else { eval { $Kernel::OM->Get('Kernel::System::Cache')->CleanUp( Type => 'Ticket' ) } }
    return;
}

sub _Enabled { return $Kernel::OM->Get('Kernel::Config')->Get('D724::TicketAudit::Enabled') ? 1 : 0 }
sub _Log { my ( $Self, $Message ) = @_; $Kernel::OM->Get('Kernel::System::Log')->Log( Priority => 'error', Message => $Message ); return }
sub _Error { my ( $Self, $Error ) = @_; return { Success => 0, Error => $Error } }

1;
