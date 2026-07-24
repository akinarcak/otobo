# --
# D724 ESM is an enterprise service management platform based on OTOBO.
# Copyright (C) 2026 Data Market Bilgi Hizmetleri A.S.
# SPDX-License-Identifier: GPL-3.0-only
# --

package Kernel::System::D724::TenantDirectory;

use v5.24;
use strict;
use warnings;

our $VERSION = '0.2.1';
our @ObjectDependencies = (
    'Kernel::System::D724::Audit',
    'Kernel::System::D724::TenantGuard',
    'Kernel::System::DB',
    'Kernel::System::Log',
    'Kernel::System::User',
);

my %ValidTenantStatus = map { $_ => 1 } qw(active suspended retired);
my %ValidRole = map { $_ => 1 } qw(requester agent service_owner auditor tenant_admin);

sub new { return bless {}, $_[0] }

sub Bootstrap {
    my ( $Self, %Param ) = @_;
    return $Self->_TransactionRun( Code => sub { return $Self->_Bootstrap(%Param) } );
}

sub _Bootstrap {
    my ( $Self, %Param ) = @_;
    return $Self->_Error('CONFIRMATION_REQUIRED') if !$Param{Confirm};
    return $Self->_Error('USER_ID_INVALID') if !$Self->_UserExists( $Param{UserID} );
    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');
    $DBObject->Prepare( SQL => 'SELECT COUNT(*) FROM d724_tenant' );
    my ($Count) = $DBObject->FetchrowArray();
    return $Self->_Error('ALREADY_BOOTSTRAPPED') if $Count;
    my $Tenant = $Self->_TenantInsert(
        TenantID => $Param{TenantID}, Name => $Param{Name}, UserID => $Param{UserID},
    );
    return $Tenant if !$Tenant->{Success};
    my $Membership = $Self->_MembershipUpsert(
        TenantID => $Param{TenantID}, MemberUserID => $Param{UserID},
        Role => 'tenant_admin', UserID => $Param{UserID},
    );
    return $Membership if !$Membership->{Success};
    my $TenantAudit = $Self->_AuditRecord(
        TenantID => $Param{TenantID}, UserID => $Param{UserID}, Action => 'tenant.created',
        ObjectType => 'tenant', ObjectID => $Param{TenantID}, DedupeKey => "tenant:$Param{TenantID}:created",
        FromState => q{}, ToState => 'active', Details => { name => $Tenant->{Data}->{Name}, version => 1, bootstrap => 1 },
    );
    return $Self->_Error('AUDIT_WRITE_FAILED') if !$TenantAudit->{Success};
    my $MembershipAudit = $Self->_MembershipAudit(
        %{$Membership->{Data}}, ActorUserID => $Param{UserID}, Action => 'tenant.membership.granted', FromState => q{},
    );
    return $Self->_Error('AUDIT_WRITE_FAILED') if !$MembershipAudit->{Success};
    return { Success => 1, Data => { Tenant => $Tenant->{Data}, Membership => $Membership->{Data} } };
}

sub TenantCreate {
    my ( $Self, %Param ) = @_;
    return $Self->_TransactionRun( Code => sub { return $Self->_TenantCreate(%Param) } );
}

sub _TenantCreate {
    my ( $Self, %Param ) = @_;
    my $Auth = $Self->_Authorize( %Param, Action => 'tenant.manage' );
    return $Auth if !$Auth->{Success};
    my $Tenant = $Self->_TenantInsert(%Param);
    return $Tenant if !$Tenant->{Success};
    my $Audit = $Self->_AuditRecord(
        TenantID => $Param{TenantID}, UserID => $Param{UserID}, Action => 'tenant.created',
        ObjectType => 'tenant', ObjectID => $Param{TenantID}, DedupeKey => "tenant:$Param{TenantID}:created",
        FromState => q{}, ToState => 'active', Details => { name => $Tenant->{Data}->{Name}, version => 1, bootstrap => 0 },
    );
    return $Self->_Error('AUDIT_WRITE_FAILED') if !$Audit->{Success};
    return $Tenant;
}

sub TenantGet {
    my ( $Self, %Param ) = @_;
    my $Auth = $Self->_Authorize( %Param, Action => 'tenant.manage' );
    return $Auth if !$Auth->{Success};
    my $Data = $Self->_TenantRowGet( TenantID => $Param{TenantID} );
    return $Self->_Error('NOT_FOUND') if !$Data;
    return { Success => 1, Data => $Data };
}

sub TenantUpdate {
    my ( $Self, %Param ) = @_;
    return $Self->_TransactionRun( Code => sub { return $Self->_TenantUpdate(%Param) } );
}

sub _TenantUpdate {
    my ( $Self, %Param ) = @_;
    my $Auth = $Self->_Authorize( %Param, Action => 'tenant.manage' );
    return $Auth if !$Auth->{Success};
    return $Self->_Error('VERSION_REQUIRED') if !$Self->_PositiveInteger( $Param{ExpectedVersion} );
    my $Current = $Self->_TenantRowGet( TenantID => $Param{TenantID} );
    return $Self->_Error('NOT_FOUND') if !$Current;
    return $Self->_Error('VERSION_CONFLICT') if $Current->{Version} != $Param{ExpectedVersion};
    $Param{Name}   //= $Current->{Name};
    $Param{Status} //= $Current->{Status};
    return $Self->_Error('TENANT_DEACTIVATION_REQUIRES_PLATFORM_ADMIN')
        if $Param{Status} ne 'active' && ( $Auth->{Reason} // q{} ) ne 'ALLOW_PLATFORM_ADMIN';
    my $Validation = $Self->_TenantValuesValidate(%Param);
    return $Validation if !$Validation->{Success};
    my @Values = ( $Param{Name}, $Param{Status}, $Param{UserID}, $Param{TenantID}, $Param{ExpectedVersion} );
    my @Bind = map { \$_ } @Values;
    my $Success = $Kernel::OM->Get('Kernel::System::DB')->Do(
        SQL => 'UPDATE d724_tenant SET name = ?, status = ?, version = version + 1, '
            . 'change_time = current_timestamp, change_by = ? WHERE key_name = ? AND version = ?',
        Bind => \@Bind,
    );
    return $Self->_Error('DATABASE_ERROR') if !$Success;
    my $Updated = $Self->_TenantRowGet( TenantID => $Param{TenantID} );
    return $Self->_Error('VERSION_CONFLICT') if !$Updated || $Updated->{Version} != $Param{ExpectedVersion} + 1;
    my $Audit = $Self->_AuditRecord(
        TenantID => $Param{TenantID}, UserID => $Param{UserID}, Action => 'tenant.updated',
        ObjectType => 'tenant', ObjectID => $Param{TenantID},
        DedupeKey => "tenant:$Param{TenantID}:version:$Updated->{Version}",
        FromState => $Current->{Status}, ToState => $Updated->{Status},
        Details => { name => $Updated->{Name}, version => $Updated->{Version} },
    );
    return $Self->_Error('AUDIT_WRITE_FAILED') if !$Audit->{Success};
    return { Success => 1, Data => $Updated };
}

sub MembershipGrant {
    my ( $Self, %Param ) = @_;
    return $Self->_TransactionRun( Code => sub { return $Self->_MembershipGrant(%Param) } );
}

sub _MembershipGrant {
    my ( $Self, %Param ) = @_;
    my $Auth = $Self->_Authorize( %Param, Action => 'tenant.manage' );
    return $Auth if !$Auth->{Success};
    return $Self->_Error('TENANT_NOT_FOUND') if !$Self->_TenantLock( TenantID => $Param{TenantID} );
    my $Before = $Self->_MembershipRowGet(%Param);
    my $Membership = $Self->_MembershipUpsert(%Param);
    return $Membership if !$Membership->{Success};
    my $Audit = $Self->_MembershipAudit(
        %{$Membership->{Data}}, ActorUserID => $Param{UserID}, Action => 'tenant.membership.granted',
        FromState => $Before ? $Before->{Status} : q{},
    );
    return $Self->_Error('AUDIT_WRITE_FAILED') if !$Audit->{Success};
    return $Membership;
}

sub MembershipRevoke {
    my ( $Self, %Param ) = @_;
    return $Self->_TransactionRun( Code => sub { return $Self->_MembershipRevoke(%Param) } );
}

sub _MembershipRevoke {
    my ( $Self, %Param ) = @_;
    my $Auth = $Self->_Authorize( %Param, Action => 'tenant.manage' );
    return $Auth if !$Auth->{Success};
    return $Self->_Error('ROLE_INVALID') if !$ValidRole{ $Param{Role} // q{} };
    return $Self->_Error('MEMBER_USER_ID_INVALID') if !$Self->_PositiveInteger( $Param{MemberUserID} );
    return $Self->_Error('TENANT_NOT_FOUND') if !$Self->_TenantLock( TenantID => $Param{TenantID} );
    my $Before = $Self->_MembershipRowGet(%Param);
    return $Self->_Error('MEMBERSHIP_NOT_FOUND') if !$Before;
    if ( $Param{Role} eq 'tenant_admin' ) {
        my ( $TenantID, $MemberUserID ) = @Param{qw(TenantID MemberUserID)};
        my $DBObject = $Kernel::OM->Get('Kernel::System::DB');
        $DBObject->Prepare(
            SQL => "SELECT status FROM d724_tenant_agent_role WHERE tenant_id = ? AND user_id = ? AND role_name = 'tenant_admin'",
            Bind => [ \$TenantID, \$MemberUserID ], Limit => 1,
        );
        my ($TargetStatus) = $DBObject->FetchrowArray();
        if ( ( $TargetStatus // q{} ) eq 'active' ) {
            $DBObject->Prepare(
                SQL => "SELECT COUNT(*) FROM d724_tenant_agent_role WHERE tenant_id = ? AND role_name = 'tenant_admin' AND status = 'active'",
                Bind => [ \$TenantID ],
            );
            my ($AdminCount) = $DBObject->FetchrowArray();
            return $Self->_Error('LAST_TENANT_ADMIN') if $AdminCount <= 1;
        }
    }
    my $Version = $Before->{Version};
    if ( $Before->{Status} ne 'revoked' ) {
        my @Values = ( $Param{UserID}, $Param{TenantID}, $Param{MemberUserID}, $Param{Role}, $Before->{Version} );
        my @Bind = map { \$_ } @Values;
        my $Success = $Kernel::OM->Get('Kernel::System::DB')->Do(
            SQL => "UPDATE d724_tenant_agent_role SET status = 'revoked', version = version + 1, change_time = current_timestamp, change_by = ? "
                . 'WHERE tenant_id = ? AND user_id = ? AND role_name = ? AND version = ?',
            Bind => \@Bind,
        );
        return $Self->_Error('DATABASE_ERROR') if !$Success;
        $Version++;
    }
    my $Data = { TenantID => $Param{TenantID}, MemberUserID => $Param{MemberUserID}, Role => $Param{Role}, Status => 'revoked', Version => $Version };
    my $Audit = $Self->_MembershipAudit(
        %{$Data}, ActorUserID => $Param{UserID}, Action => 'tenant.membership.revoked', FromState => $Before->{Status},
    );
    return $Self->_Error('AUDIT_WRITE_FAILED') if !$Audit->{Success};
    return { Success => 1, Data => $Data, IdempotentReplay => $Before->{Status} eq 'revoked' ? 1 : 0 };
}

sub MembershipList {
    my ( $Self, %Param ) = @_;
    my $Auth = $Self->_Authorize( %Param, Action => 'tenant.manage' );
    return $Auth if !$Auth->{Success};
    my $TenantID = $Param{TenantID};
    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');
    $DBObject->Prepare(
        SQL => 'SELECT user_id, role_name, status, version, create_time, create_by, change_time, change_by '
            . 'FROM d724_tenant_agent_role WHERE tenant_id = ? ORDER BY user_id, role_name',
        Bind => [ \$TenantID ],
    );
    my @Data;
    while ( my @Row = $DBObject->FetchrowArray() ) {
        push @Data, {
            TenantID => $TenantID, MemberUserID => $Row[0], Role => $Row[1], Status => $Row[2], Version => $Row[3],
            CreateTime => $Row[4], CreateBy => $Row[5], ChangeTime => $Row[6], ChangeBy => $Row[7],
        };
    }
    return { Success => 1, Data => \@Data };
}

sub ContextGet {
    my ( $Self, %Param ) = @_;
    return $Self->_Error('USER_ID_INVALID') if !$Self->_PositiveInteger( $Param{UserID} );
    my $UserID = $Param{UserID};
    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');
    $DBObject->Prepare(
        SQL => "SELECT r.tenant_id, r.role_name FROM d724_tenant_agent_role r "
            . "INNER JOIN d724_tenant t ON t.key_name = r.tenant_id "
            . "WHERE r.user_id = ? AND r.status = 'active' AND t.status = 'active' ORDER BY r.tenant_id, r.role_name",
        Bind => [ \$UserID ],
    );
    my %Bindings;
    while ( my ( $TenantID, $Role ) = $DBObject->FetchrowArray() ) {
        push @{ $Bindings{$TenantID} }, $Role if $ValidRole{$Role};
    }
    return $Self->_Error('NO_ACTIVE_MEMBERSHIP') if !keys %Bindings;
    return {
        Success => 1,
        Subject => {
            ID           => "agent:$UserID",
            TenantIDs    => [ sort keys %Bindings ],
            RoleBindings => \%Bindings,
        },
    };
}

sub _TenantInsert {
    my ( $Self, %Param ) = @_;
    return $Self->_Error('USER_ID_INVALID') if !$Self->_UserExists( $Param{UserID} );
    my $Validation = $Self->_TenantValuesValidate(%Param);
    return $Validation if !$Validation->{Success};
    return $Self->_Error('TENANT_EXISTS') if $Self->_TenantRowGet( TenantID => $Param{TenantID} );
    my @Values = ( $Param{TenantID}, $Param{Name}, 'active', 1, $Param{UserID}, $Param{UserID} );
    my @Bind = map { \$_ } @Values;
    my $Success = $Kernel::OM->Get('Kernel::System::DB')->Do(
        SQL => 'INSERT INTO d724_tenant (key_name, name, status, version, create_time, create_by, change_time, change_by) '
            . 'VALUES (?, ?, ?, ?, current_timestamp, ?, current_timestamp, ?)',
        Bind => \@Bind,
    );
    return $Self->_Error('DATABASE_ERROR') if !$Success;
    return { Success => 1, Data => $Self->_TenantRowGet( TenantID => $Param{TenantID} ) };
}

sub _MembershipUpsert {
    my ( $Self, %Param ) = @_;
    return $Self->_Error('ROLE_INVALID') if !$ValidRole{ $Param{Role} // q{} };
    return $Self->_Error('MEMBER_USER_ID_INVALID') if !$Self->_UserExists( $Param{MemberUserID} );
    my $Tenant = $Self->_TenantRowGet( TenantID => $Param{TenantID} );
    return $Self->_Error('TENANT_NOT_FOUND') if !$Tenant;
    return $Self->_Error('TENANT_NOT_ACTIVE') if $Tenant->{Status} ne 'active';
    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');
    my ( $TenantID, $MemberUserID, $Role ) = @Param{qw(TenantID MemberUserID Role)};
    $DBObject->Prepare(
        SQL => 'SELECT id, status, version FROM d724_tenant_agent_role WHERE tenant_id = ? AND user_id = ? AND role_name = ?',
        Bind => [ \$TenantID, \$MemberUserID, \$Role ], Limit => 1,
    );
    my ( $ID, $Status, $Version ) = $DBObject->FetchrowArray();
    my $Success;
    if ($ID) {
        if ( $Status ne 'active' ) {
            my @Values = ( $Param{UserID}, $ID, $Version );
            my @Bind = map { \$_ } @Values;
            $Success = $DBObject->Do(
                SQL => "UPDATE d724_tenant_agent_role SET status = 'active', version = version + 1, change_time = current_timestamp, change_by = ? WHERE id = ? AND version = ?",
                Bind => \@Bind,
            );
            $Version++;
        }
        else {
            $Success = 1;
        }
    }
    else {
        my @Values = ( $TenantID, $MemberUserID, $Role, $Param{UserID}, $Param{UserID} );
        my @Bind = map { \$_ } @Values;
        $Success = $DBObject->Do(
            SQL => 'INSERT INTO d724_tenant_agent_role '
                . '(tenant_id, user_id, role_name, status, version, create_time, create_by, change_time, change_by) '
                . "VALUES (?, ?, ?, 'active', 1, current_timestamp, ?, current_timestamp, ?)",
            Bind => \@Bind,
        );
        $Version = 1;
    }
    return $Self->_Error('DATABASE_ERROR') if !$Success;
    return { Success => 1, Data => { TenantID => $TenantID, MemberUserID => $MemberUserID, Role => $Role, Status => 'active', Version => $Version }, IdempotentReplay => $ID && $Status eq 'active' ? 1 : 0 };
}

sub _TenantLock {
    my ( $Self, %Param ) = @_;
    my $TenantID = $Param{TenantID};
    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');
    $DBObject->Prepare(
        SQL => 'SELECT id FROM d724_tenant WHERE key_name = ? FOR UPDATE',
        Bind => [ \$TenantID ],
    );
    my ($ID) = $DBObject->FetchrowArray();
    return $ID;
}

sub _MembershipRowGet {
    my ( $Self, %Param ) = @_;
    my ( $TenantID, $MemberUserID, $Role ) = @Param{qw(TenantID MemberUserID Role)};
    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');
    $DBObject->Prepare(
        SQL => 'SELECT status, version FROM d724_tenant_agent_role WHERE tenant_id = ? AND user_id = ? AND role_name = ?',
        Bind => [ \$TenantID, \$MemberUserID, \$Role ], Limit => 1,
    );
    my ( $Status, $Version ) = $DBObject->FetchrowArray();
    return if !defined $Status;
    return { Status => $Status, Version => $Version };
}

sub _MembershipAudit {
    my ( $Self, %Param ) = @_;
    return $Self->_AuditRecord(
        TenantID => $Param{TenantID}, UserID => $Param{ActorUserID}, Action => $Param{Action},
        ObjectType => 'tenant_membership', ObjectID => "$Param{MemberUserID}:$Param{Role}",
        DedupeKey => "tenant:$Param{TenantID}:membership:$Param{MemberUserID}:$Param{Role}:version:$Param{Version}",
        FromState => $Param{FromState}, ToState => $Param{Status},
        Details => { member_user_id => $Param{MemberUserID}, role => $Param{Role}, version => $Param{Version} },
    );
}

sub _AuditRecord {
    my ( $Self, %Param ) = @_;
    return $Kernel::OM->Get('Kernel::System::D724::Audit')->Record(
        TenantID => $Param{TenantID}, ActorType => 'agent', ActorID => "agent:$Param{UserID}",
        Action => $Param{Action}, ObjectType => $Param{ObjectType}, ObjectID => "$Param{ObjectID}",
        CorrelationID => "tenant:$Param{TenantID}", DedupeKey => $Param{DedupeKey},
        FromState => $Param{FromState}, ToState => $Param{ToState}, Outcome => 'success', Details => $Param{Details},
    );
}

sub _TransactionRun {
    my ( $Self, %Param ) = @_;
    return $Self->_Error('TRANSACTION_CODE_INVALID') if ref $Param{Code} ne 'CODE';
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
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error', Message => "D724 tenant directory transaction failed: $Failure",
        );
        return $Self->_Error('TRANSACTION_FAILED');
    }
    return $Result;
}

sub _Authorize {
    my ( $Self, %Param ) = @_;
    return $Self->_Error('USER_ID_INVALID') if !$Self->_UserExists( $Param{UserID} );
    my $Decision = $Kernel::OM->Get('Kernel::System::D724::TenantGuard')->DecisionGet(
        Subject => $Param{Subject}, Resource => { TenantID => $Param{TenantID} }, Action => $Param{Action},
    );
    return $Self->_Error( 'FORBIDDEN', $Decision->{Reason} ) if !$Decision->{Allowed};
    return {
        Success    => 1,
        Reason     => $Decision->{Reason},
        MatchedRole => $Decision->{MatchedRole},
    };
}

sub _TenantValuesValidate {
    my ( $Self, %Param ) = @_;
    return $Self->_Error('TENANT_ID_INVALID')
        if !defined $Param{TenantID} || $Param{TenantID} !~ m{\A[a-zA-Z0-9][a-zA-Z0-9._:-]{0,127}\z}smx;
    return $Self->_Error('NAME_INVALID')
        if !defined $Param{Name} || !length $Param{Name} || length $Param{Name} > 200 || $Param{Name} =~ m{[\x00-\x1f]}smx;
    return $Self->_Error('STATUS_INVALID') if defined $Param{Status} && !$ValidTenantStatus{ $Param{Status} };
    return { Success => 1 };
}

sub _TenantRowGet {
    my ( $Self, %Param ) = @_;
    return if !defined $Param{TenantID};
    my $TenantID = $Param{TenantID};
    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');
    $DBObject->Prepare(
        SQL => 'SELECT id, key_name, name, status, version, create_time, create_by, change_time, change_by '
            . 'FROM d724_tenant WHERE key_name = ?', Bind => [ \$TenantID ], Limit => 1,
    );
    my @Row = $DBObject->FetchrowArray();
    return if !@Row;
    my @Columns = qw(ID TenantID Name Status Version CreateTime CreateBy ChangeTime ChangeBy);
    my %Data; @Data{@Columns} = @Row;
    return \%Data;
}

sub _UserExists {
    my ( $Self, $UserID ) = @_;
    return if !$Self->_PositiveInteger($UserID);
    return $Kernel::OM->Get('Kernel::System::User')->UserLookup( UserID => $UserID, Silent => 1 ) ? 1 : 0;
}

sub _PositiveInteger { return defined $_[1] && $_[1] =~ m{\A[1-9][0-9]*\z}smx ? 1 : 0 }

sub _Error {
    my ( $Self, $Code, $Reason ) = @_;
    my $Error = { Success => 0, Error => $Code };
    $Error->{Reason} = $Reason if defined $Reason;
    return $Error;
}

1;
