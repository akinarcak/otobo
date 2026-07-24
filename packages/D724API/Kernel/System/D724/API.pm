# --
# Copyright (C) 2026 Data Market Bilgi Hizmetleri A.S.
# SPDX-License-Identifier: GPL-3.0-only
# --
package Kernel::System::D724::API;

use v5.24;
use strict;
use warnings;

our $VERSION = '0.3.0';
our @ObjectDependencies = (
    'Kernel::System::CustomerUser',
    'Kernel::System::D724::APIAuth',
    'Kernel::System::D724::Request',
    'Kernel::System::DB',
);

sub new { return bless {}, $_[0] }

sub TicketList {
    my ( $Self, %Param ) = @_;

    my $Limit = $Param{Limit} // 50;
    return $Self->_Error('LIMIT_INVALID')
        if $Limit !~ m{\A[1-9][0-9]*\z}smx || $Limit > 100;
    my $AfterID = $Param{AfterID} // 0;
    return $Self->_Error('CURSOR_INVALID')
        if $AfterID !~ m{\A[0-9]+\z}smx;

    my $Authorization = $Self->_Authorize( %Param, Action => 'case.read' );
    return $Authorization if !$Authorization->{Success};
    my $TenantID = $Authorization->{Data}->{TenantID};

    my $DB = $Kernel::OM->Get('Kernel::System::DB');
    my @Values = ( $TenantID, $AfterID );
    my @Bind   = map { \$_ } @Values;
    my $Prepared = $DB->Prepare(
        SQL => 'SELECT t.id, t.tn, t.title, q.name, ts.name, tp.name, t.customer_id, t.create_time, t.change_time '
            . 'FROM d724_ticket_scope s INNER JOIN ticket t ON t.id = s.ticket_id '
            . 'INNER JOIN queue q ON q.id = t.queue_id '
            . 'INNER JOIN ticket_state ts ON ts.id = t.ticket_state_id '
            . 'INNER JOIN ticket_priority tp ON tp.id = t.ticket_priority_id '
            . "WHERE s.tenant_id = ? AND s.status = 'active' AND t.id > ? ORDER BY t.id ASC",
        Bind  => \@Bind,
        Limit => $Limit + 1,
    );
    return $Self->_Error('DATABASE_ERROR') if !$Prepared;

    my @Items;
    while ( my @Row = $DB->FetchrowArray() ) {
        push @Items, $Self->_TicketRow(@Row);
    }
    my $HasMore = @Items > $Limit ? 1 : 0;
    pop @Items if $HasMore;
    my $Next = $HasMore && @Items ? $Items[-1]->{id} : undef;

    return {
        Success => 1,
        Data    => {
            items       => \@Items,
            count       => scalar @Items,
            next_cursor => $Next,
        },
        Meta => $Self->_Meta($Authorization),
    };
}

sub TicketGet {
    my ( $Self, %Param ) = @_;
    return $Self->_Error('TICKET_ID_INVALID')
        if ( $Param{TicketID} // q{} ) !~ m{\A[1-9][0-9]*\z}smx;

    my $Authorization = $Self->_Authorize( %Param, Action => 'case.read' );
    return $Authorization if !$Authorization->{Success};
    my $TenantID = $Authorization->{Data}->{TenantID};
    my $TicketID = $Param{TicketID};

    my $DB = $Kernel::OM->Get('Kernel::System::DB');
    my @Values = ( $TenantID, $TicketID );
    my @Bind   = map { \$_ } @Values;
    my $Prepared = $DB->Prepare(
        SQL => 'SELECT t.id, t.tn, t.title, q.name, ts.name, tp.name, t.customer_id, t.create_time, t.change_time '
            . 'FROM d724_ticket_scope s INNER JOIN ticket t ON t.id = s.ticket_id '
            . 'INNER JOIN queue q ON q.id = t.queue_id '
            . 'INNER JOIN ticket_state ts ON ts.id = t.ticket_state_id '
            . 'INNER JOIN ticket_priority tp ON tp.id = t.ticket_priority_id '
            . "WHERE s.tenant_id = ? AND s.status = 'active' AND t.id = ?",
        Bind => \@Bind, Limit => 1,
    );
    return $Self->_Error('DATABASE_ERROR') if !$Prepared;
    my @Row = $DB->FetchrowArray();

    # Deliberately hide whether a ticket belongs to another tenant.
    return $Self->_Error('NOT_FOUND') if !@Row;
    return {
        Success => 1,
        Data    => $Self->_TicketRow(@Row),
        Meta    => $Self->_Meta($Authorization),
    };
}

sub RequestCreate {
    my ( $Self, %Param ) = @_;
    return $Self->_Error('CATALOG_ITEM_ID_INVALID')
        if ( $Param{CatalogItemID} // q{} ) !~ m{\A[1-9][0-9]*\z}smx;
    return $Self->_Error('REQUESTER_LOGIN_INVALID')
        if !length( $Param{RequesterLogin} // q{} ) || length $Param{RequesterLogin} > 200;
    return $Self->_Error('ANSWERS_INVALID') if ref $Param{Answers} ne 'HASH';

    my $Authorization = $Self->_Authorize( %Param, Action => 'case.create' );
    return $Authorization if !$Authorization->{Success};
    my $TenantID = $Authorization->{Data}->{TenantID};
    my $Customer = $Self->_CustomerValidate(
        TenantID => $TenantID, RequesterLogin => $Param{RequesterLogin},
    );
    return $Customer if !$Customer->{Success};

    my $Result = $Kernel::OM->Get('Kernel::System::D724::Request')->CustomerSubmit(
        CustomerUserID => $Param{RequesterLogin},
        CustomerID     => $TenantID,
        CatalogItemID  => $Param{CatalogItemID},
        Answers        => $Param{Answers},
        IdempotencyKey => $Param{IdempotencyKey},
    );
    return $Result if !$Result->{Success};
    return {
        Success          => 1,
        Data             => $Self->_RequestProject( $Result->{Data} ),
        IdempotentReplay => $Result->{IdempotentReplay} ? 1 : 0,
        Meta             => $Self->_Meta($Authorization),
    };
}

sub RequestGet {
    my ( $Self, %Param ) = @_;
    return $Self->_Error('REQUEST_ID_INVALID')
        if ( $Param{RequestID} // q{} ) !~ m{\A[1-9][0-9]*\z}smx;
    return $Self->_Error('REQUESTER_LOGIN_INVALID')
        if !length( $Param{RequesterLogin} // q{} ) || length $Param{RequesterLogin} > 200;

    my $Authorization = $Self->_Authorize( %Param, Action => 'case.read' );
    return $Authorization if !$Authorization->{Success};
    my $TenantID = $Authorization->{Data}->{TenantID};
    my $Customer = $Self->_CustomerValidate(
        TenantID => $TenantID, RequesterLogin => $Param{RequesterLogin},
    );
    return $Customer if !$Customer->{Success};

    my $Result = $Kernel::OM->Get('Kernel::System::D724::Request')->CustomerGet(
        CustomerUserID => $Param{RequesterLogin},
        CustomerID     => $TenantID,
        RequestID      => $Param{RequestID},
    );
    return $Result if !$Result->{Success};
    return {
        Success => 1,
        Data    => $Self->_RequestProject( $Result->{Data} ),
        Meta    => $Self->_Meta($Authorization),
    };
}

sub _Authorize {
    my ( $Self, %Param ) = @_;
    return $Kernel::OM->Get('Kernel::System::D724::APIAuth')->Authorize(
        AccessToken => $Param{AccessToken},
        TenantID    => $Param{TenantID},
        Action      => $Param{Action},
    );
}

sub _TicketRow {
    my ( $Self, @Row ) = @_;
    return {
        id          => 0 + $Row[0],
        number      => $Row[1],
        title       => $Row[2],
        queue       => $Row[3],
        state       => $Row[4],
        priority    => $Row[5],
        tenant_id   => $Row[6],
        created_at  => $Row[7],
        changed_at  => $Row[8],
    };
}

sub _CustomerValidate {
    my ( $Self, %Param ) = @_;
    my %Customer = $Kernel::OM->Get('Kernel::System::CustomerUser')->CustomerUserDataGet(
        User => $Param{RequesterLogin},
    );
    return $Self->_Error('REQUESTER_NOT_FOUND')
        if !%Customer
        || ( $Customer{UserCustomerID} // q{} ) ne $Param{TenantID}
        || ( defined $Customer{ValidID} && $Customer{ValidID} != 1 );
    return { Success => 1 };
}

sub _RequestProject {
    my ( $Self, $Request ) = @_;
    my @Approvals = map {
        {
            id => 0 + $_->{ApprovalID}, sequence => 0 + $_->{Sequence},
            role => $_->{ApproverRole}, status => $_->{Status}, version => 0 + $_->{Version},
        }
    } @{ $Request->{Approvals} // [] };
    my @Tasks = map {
        {
            id => 0 + $_->{TaskID}, key => $_->{Key}, name => $_->{Name},
            type => $_->{Type}, status => $_->{Status}, version => 0 + $_->{Version},
        }
    } @{ $Request->{Tasks} // [] };
    return {
        id              => 0 + $Request->{RequestID},
        number          => $Request->{RequestNumber},
        tenant_id       => $Request->{TenantID},
        catalog_item_id => 0 + $Request->{CatalogItemID},
        status          => $Request->{Status},
        version         => 0 + $Request->{Version},
        approvals       => \@Approvals,
        tasks           => \@Tasks,
        created_at      => $Request->{CreateTime},
        changed_at      => $Request->{ChangeTime},
    };
}

sub _Meta {
    my ( $Self, $Authorization ) = @_;
    return {
        tenant_id     => $Authorization->{Data}->{TenantID},
        rate_remaining => 0 + $Authorization->{Data}->{Remaining},
    };
}

sub _Error {
    my ( $Self, $Error ) = @_;
    return { Success => 0, Error => $Error, Reason => $Error };
}

1;
