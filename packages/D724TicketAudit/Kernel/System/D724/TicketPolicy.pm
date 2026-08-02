# --
# Copyright (C) 2026 Data Market Bilgi Hizmetleri A.S.
# SPDX-License-Identifier: GPL-3.0-only
# --
package Kernel::System::D724::TicketPolicy;

use v5.24;
use strict;
use warnings;

our $VERSION = '0.8.6';

our @ObjectDependencies = (
    'Kernel::System::CustomerUser',
    'Kernel::System::D724::TenantDirectory',
    'Kernel::System::D724::TenantGuard',
    'Kernel::System::DB',
    'Kernel::System::Log',
);

sub new {
    my ($Type) = @_;
    return bless {}, $Type;
}

sub SearchScopeApply {
    my ( $Self, %Param ) = @_;
    return $Self->_Deny('PARAM_INVALID') if ref $Param{Param} ne 'HASH';

    my %Search = %{ $Param{Param} };
    my $Context = $Self->ContextResolve(%Search);
    return $Context if !$Context->{Success};

    if ( $Context->{Unrestricted} ) {
        return { Success => 1, Param => \%Search, Context => $Context };
    }

    return $Self->_Deny('CUSTOMER_ID_RAW_FORBIDDEN') if exists $Search{CustomerIDRaw};

    my %Allowed = map { $_ => 1 } @{ $Context->{TenantIDs} };
    my @Requested;
    if ( exists $Search{CustomerID} ) {
        @Requested = ref $Search{CustomerID} eq 'ARRAY'
            ? @{ $Search{CustomerID} }
            : ( $Search{CustomerID} );
        @Requested = grep { defined $_ && $Allowed{$_} } @Requested;
        return $Self->_Deny('EMPTY_TENANT_INTERSECTION') if !@Requested;
    }
    else {
        @Requested = sort keys %Allowed;
    }

    $Search{CustomerID} = \@Requested;
    return { Success => 1, Param => \%Search, Context => $Context };
}

sub TicketAccessCheck {
    my ( $Self, %Param ) = @_;
    return $Self->_Deny('TICKET_ID_INVALID')
        if ( $Param{TicketID} // q{} ) !~ m{\A[1-9][0-9]*\z}smx;

    my $Context = $Self->ContextResolve(%Param);
    return $Context if !$Context->{Success};
    return { Success => 1, Context => $Context, Reason => 'ALLOW_PLATFORM_ADMIN' }
        if $Context->{Unrestricted};

    my $TicketID = $Param{TicketID};
    my $DB = $Kernel::OM->Get('Kernel::System::DB');
    $DB->Prepare(
        SQL => "SELECT s.tenant_id FROM d724_ticket_scope s INNER JOIN d724_tenant t ON t.key_name = s.tenant_id "
            . "WHERE s.ticket_id = ? AND s.status = 'active' AND t.status = 'active'",
        Bind => [ \$TicketID ], Limit => 1,
    );
    my ($TenantID) = $DB->FetchrowArray();
    return $Self->_Deny('TICKET_SCOPE_MISSING') if !defined $TenantID || !length $TenantID;

    my %Allowed = map { $_ => 1 } @{ $Context->{TenantIDs} };
    return $Self->_Deny('CROSS_TENANT') if !$Allowed{$TenantID};

    my $Action = $Param{Action} // 'case.read';
    my $Decision = $Kernel::OM->Get('Kernel::System::D724::TenantGuard')->DecisionGet(
        Subject => $Context->{Subject}, Resource => { TenantID => $TenantID }, Action => $Action,
    );
    return $Self->_Deny( $Decision->{Reason} // 'ACTION_DENIED' ) if !$Decision->{Allowed};
    return { Success => 1, Context => $Context, TenantID => $TenantID, Reason => 'ALLOW_TENANT_SCOPE' };
}

sub ContextResolve {
    my ( $Self, %Param ) = @_;

    if ( $Param{UserID} ) {
        my $Context = $Kernel::OM->Get('Kernel::System::D724::TenantDirectory')->ContextGet(
            UserID => $Param{UserID},
        );
        return $Self->_Deny( $Context->{Error} // 'AGENT_CONTEXT_DENIED' ) if !$Context->{Success};
        my $Scope = $Kernel::OM->Get('Kernel::System::D724::TenantGuard')->ScopeGet(
            Subject => $Context->{Subject},
        );
        return $Self->_Deny( $Scope->{Reason} // 'AGENT_SCOPE_DENIED' ) if !$Scope->{Success};
        return { Success => 1, %{$Scope}, Subject => $Context->{Subject}, SubjectType => 'Agent' };
    }

    if ( defined $Param{CustomerUserID} && length $Param{CustomerUserID} ) {
        my %Customer = $Kernel::OM->Get('Kernel::System::CustomerUser')->CustomerUserDataGet(
            User => $Param{CustomerUserID},
        );
        my $TenantID = $Customer{UserCustomerID};
        return $Self->_Deny('CUSTOMER_TENANT_MISSING') if !defined $TenantID || !length $TenantID;
        return $Self->_Deny('CUSTOMER_TENANT_INACTIVE') if !$Self->_TenantActive( TenantID => $TenantID );
        return {
            Success => 1, TenantIDs => [$TenantID], Unrestricted => 0,
            Subject => { ID => "customer:$Param{CustomerUserID}", TenantIDs => [$TenantID], Roles => ['requester'] },
            SubjectType => 'Customer', Reason => 'ALLOW_CUSTOMER_TENANT',
        };
    }

    return $Self->_Deny('SUBJECT_CONTEXT_MISSING');
}

sub _TenantActive {
    my ( $Self, %Param ) = @_;
    my $TenantID = $Param{TenantID};
    my $DB = $Kernel::OM->Get('Kernel::System::DB');
    $DB->Prepare(
        SQL => "SELECT 1 FROM d724_tenant WHERE key_name = ? AND status = 'active'",
        Bind => [ \$TenantID ], Limit => 1,
    );
    my ($Found) = $DB->FetchrowArray();
    return $Found ? 1 : 0;
}

sub _Deny {
    my ( $Self, $Reason ) = @_;
    $Kernel::OM->Get('Kernel::System::Log')->Log(
        Priority => 'error', Message => "D724_TICKET_POLICY_DENY Reason=$Reason",
    );
    return { Success => 0, Error => 'FORBIDDEN', Reason => $Reason, TenantIDs => [] };
}

1;
