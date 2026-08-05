# --
# Copyright (C) 2026 Data Market Bilgi Hizmetleri A.S.
# SPDX-License-Identifier: GPL-3.0-only
# --
package Kernel::System::CareOnCloud::SearchPolicy;

use v5.24;
use strict;
use warnings;

our $VERSION = '0.1.0';
our @ObjectDependencies = (
    'Kernel::Config', 'Kernel::System::CareOnCloud::TenantGuard',
    'Kernel::System::CareOnCloud::TicketPolicy', 'Kernel::System::Log',
);

sub new { return bless {}, $_[0] }

sub ContextCreate {
    my ( $Self, %Param ) = @_;
    return $Self->_Deny('SEARCH_POLICY_DISABLED')
        if !$Kernel::OM->Get('Kernel::Config')->Get('CareOnCloud::SearchPolicy::Enabled');
    my $Context = $Kernel::OM->Get('Kernel::System::CareOnCloud::TicketPolicy')->ContextResolve(%Param);
    return $Self->_Deny( $Context->{Reason} // 'SUBJECT_CONTEXT_DENIED' ) if !$Context->{Success};
    return $Self->_Deny('UNRESTRICTED_SEARCH_FORBIDDEN') if $Context->{Unrestricted};
    my @TenantIDs = sort @{ $Context->{TenantIDs} // [] };
    return $Self->_Deny('TENANT_SCOPE_EMPTY') if !@TenantIDs;
    my $Guard = $Kernel::OM->Get('Kernel::System::CareOnCloud::TenantGuard');
    for my $TenantID (@TenantIDs) {
        my $Decision = $Guard->DecisionGet(
            Subject => $Context->{Subject}, Resource => { TenantID => $TenantID }, Action => 'search.read',
        );
        return $Self->_Deny( $Decision->{Reason} // 'SEARCH_ACTION_DENIED' ) if !$Decision->{Allowed};
    }
    return {
        Success => 1, TenantIDs => \@TenantIDs, Subject => $Context->{Subject},
        SubjectType => $Context->{SubjectType}, PolicyVersion => '1',
    };
}

sub RequestFilterApply {
    my ( $Self, %Param ) = @_;
    return $Self->_Deny('SEARCH_POLICY_DISABLED')
        if !$Kernel::OM->Get('Kernel::Config')->Get('CareOnCloud::SearchPolicy::Enabled');
    return $Self->_Deny('SEARCH_DATA_INVALID') if ref $Param{Data} ne 'HASH';
    return $Self->_Deny('SEARCH_CONTEXT_MISSING')
        if ref $Param{Context} ne 'HASH' || !$Param{Context}->{Success};
    my $Index = $Param{Data}->{IndexName} // q{};
    my %Configured = map { $_ => 1 } @{ $Kernel::OM->Get('Kernel::Config')->Get('CareOnCloud::SearchPolicy::TenantSafeIndexes') // [] };
    my %TenantField = ( ticket => 'CustomerID' );
    return $Self->_Deny('INDEX_NOT_TENANT_SAFE') if !$Configured{$Index} || !$TenantField{$Index};
    return $Self->_Deny('TENANT_SCOPE_EMPTY')
        if ref $Param{Context}->{TenantIDs} ne 'ARRAY' || !@{ $Param{Context}->{TenantIDs} };
    my %Data = %{ $Param{Data} };
    my @Filter = ref $Data{Filter} eq 'ARRAY' ? @{ $Data{Filter} } : ();
    push @Filter, { terms => { $TenantField{$Index} => [ @{ $Param{Context}->{TenantIDs} } ] } };
    $Data{Filter} = \@Filter;
    return { Success => 1, Data => \%Data, TenantField => $TenantField{$Index}, IndexName => $Index };
}

sub _Deny {
    my ( $Self, $Reason ) = @_;
    $Kernel::OM->Get('Kernel::System::Log')->Log(
        Priority => 'error', Message => "CareOnCloud_SEARCH_POLICY_DENY Reason=$Reason",
    );
    return { Success => 0, Error => 'FORBIDDEN', Reason => $Reason };
}

1;
