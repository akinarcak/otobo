# --
# D724 ESM is an enterprise service management platform based on OTOBO.
# Copyright (C) 2026 Data Market Bilgi Hizmetleri A.S.
# SPDX-License-Identifier: GPL-3.0-only
# --

package Kernel::System::D724::TenantGuard;

use v5.24;
use strict;
use warnings;

our $VERSION = '0.1.1';

our @ObjectDependencies = (
    'Kernel::Config',
);

my %RoleActions = (
    requester => {
        map { $_ => 1 } qw(catalog.read case.create case.read case.comment)
    },
    agent => {
        map { $_ => 1 } qw(catalog.read case.create case.read case.comment case.update case.assign)
    },
    service_owner => {
        map { $_ => 1 } qw(catalog.read catalog.manage case.create case.read case.comment case.update case.assign case.delete audit.read)
    },
    auditor => {
        map { $_ => 1 } qw(catalog.read case.read audit.read)
    },
    automation => {
        map { $_ => 1 } qw(catalog.read case.create case.read case.comment case.update case.assign)
    },
    tenant_admin => {
        map { $_ => 1 } qw(catalog.read catalog.manage case.create case.read case.comment case.update case.assign case.delete audit.read tenant.manage)
    },
);

my %KnownActions = map { $_ => 1 } map { keys %{$_} } values %RoleActions;

sub new {
    my ($Type) = @_;

    return bless {}, $Type;
}

sub DecisionGet {
    my ( $Self, %Param ) = @_;

    my $PolicyVersion = $Self->_PolicyVersionGet();
    my $Deny = sub {
        my ($Reason) = @_;
        return {
            Allowed       => 0,
            Reason        => $Reason,
            PolicyVersion => $PolicyVersion,
        };
    };

    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');
    return $Deny->('DENY_POLICY_DISABLED') if !$ConfigObject->Get('D724::TenantGuard::Enabled');

    my $Action = $Param{Action};
    return $Deny->('DENY_ACTION_MISSING') if !defined $Action || !length $Action;
    return $Deny->('DENY_ACTION_UNKNOWN') if !$KnownActions{$Action};

    my $Subject = $Param{Subject};
    return $Deny->('DENY_SUBJECT_MISSING') if ref $Subject ne 'HASH';
    return $Deny->('DENY_SUBJECT_ID_MISSING') if !$Self->_IdentifierValid( $Subject->{ID} );

    my $Roles = $Subject->{Roles};
    return $Deny->('DENY_SUBJECT_ROLES_MISSING') if ref $Roles ne 'ARRAY' || !@{$Roles};

    my $SubjectTenantIDs = $Subject->{TenantIDs};
    return $Deny->('DENY_SUBJECT_TENANT_MISSING')
        if ref $SubjectTenantIDs ne 'ARRAY' || !@{$SubjectTenantIDs};
    for my $TenantID ( @{$SubjectTenantIDs} ) {
        return $Deny->('DENY_TENANT_IDENTIFIER_INVALID') if !$Self->_IdentifierValid($TenantID);
    }

    my $Resource = $Param{Resource};
    return $Deny->('DENY_RESOURCE_MISSING') if ref $Resource ne 'HASH';
    return $Deny->('DENY_RESOURCE_TENANT_MISSING')
        if !defined $Resource->{TenantID} || !length $Resource->{TenantID};
    return $Deny->('DENY_TENANT_IDENTIFIER_INVALID')
        if !$Self->_IdentifierValid( $Resource->{TenantID} );

    my %Roles = map { $_ => 1 } @{$Roles};
    if (
        $Roles{platform_admin}
        && $ConfigObject->Get('D724::TenantGuard::AllowPlatformAdmin')
        )
    {
        return {
            Allowed       => 1,
            Reason        => 'ALLOW_PLATFORM_ADMIN',
            PolicyVersion => $PolicyVersion,
        };
    }

    my %SubjectTenants = map { $_ => 1 } @{$SubjectTenantIDs};
    return $Deny->('DENY_CROSS_TENANT') if !$SubjectTenants{ $Resource->{TenantID} };

    for my $Role ( @{$Roles} ) {
        next if !$RoleActions{$Role};
        next if !$RoleActions{$Role}->{$Action};

        return {
            Allowed       => 1,
            Reason        => 'ALLOW_ROLE_ACTION',
            MatchedRole   => $Role,
            PolicyVersion => $PolicyVersion,
        };
    }

    return $Deny->('DENY_ROLE_NOT_GRANTED');
}

sub ScopeGet {
    my ( $Self, %Param ) = @_;

    my $PolicyVersion = $Self->_PolicyVersionGet();
    my $ConfigObject  = $Kernel::OM->Get('Kernel::Config');
    my $Subject       = $Param{Subject};

    return {
        Success       => 0,
        Reason        => 'DENY_POLICY_DISABLED',
        PolicyVersion => $PolicyVersion,
        TenantIDs     => [],
    } if !$ConfigObject->Get('D724::TenantGuard::Enabled');

    return {
        Success       => 0,
        Reason        => 'DENY_SUBJECT_MISSING',
        PolicyVersion => $PolicyVersion,
        TenantIDs     => [],
    } if ref $Subject ne 'HASH';

    return {
        Success       => 0,
        Reason        => 'DENY_SUBJECT_ID_MISSING',
        PolicyVersion => $PolicyVersion,
        TenantIDs     => [],
    } if !$Self->_IdentifierValid( $Subject->{ID} );

    my $Roles = $Subject->{Roles};
    return {
        Success       => 0,
        Reason        => 'DENY_SUBJECT_ROLES_MISSING',
        PolicyVersion => $PolicyVersion,
        TenantIDs     => [],
    } if ref $Roles ne 'ARRAY' || !@{$Roles};

    my %Roles = map { $_ => 1 } @{$Roles};
    my $KnownRole = $Roles{platform_admin};
    for my $Role ( keys %Roles ) {
        $KnownRole = 1 if $RoleActions{$Role};
    }
    return {
        Success       => 0,
        Reason        => 'DENY_ROLE_NOT_GRANTED',
        PolicyVersion => $PolicyVersion,
        TenantIDs     => [],
    } if !$KnownRole;

    my $TenantIDs = $Subject->{TenantIDs};
    return {
        Success       => 0,
        Reason        => 'DENY_SUBJECT_TENANT_MISSING',
        PolicyVersion => $PolicyVersion,
        TenantIDs     => [],
    } if ref $TenantIDs ne 'ARRAY' || !@{$TenantIDs};

    my %TenantIDs;
    for my $TenantID ( @{$TenantIDs} ) {
        return {
            Success       => 0,
            Reason        => 'DENY_TENANT_IDENTIFIER_INVALID',
            PolicyVersion => $PolicyVersion,
            TenantIDs     => [],
        } if !$Self->_IdentifierValid($TenantID);
        $TenantIDs{$TenantID} = 1;
    }

    my $Unrestricted =
        $Roles{platform_admin}
        && $ConfigObject->Get('D724::TenantGuard::AllowPlatformAdmin')
        ? 1
        : 0;

    return {
        Success       => 1,
        Reason        => $Unrestricted ? 'ALLOW_PLATFORM_ADMIN' : 'ALLOW_TENANT_SCOPE',
        PolicyVersion => $PolicyVersion,
        TenantIDs     => [ sort keys %TenantIDs ],
        Unrestricted  => $Unrestricted,
    };
}

sub _IdentifierValid {
    my ( $Self, $Identifier ) = @_;

    return if !defined $Identifier;
    return $Identifier =~ m{\A[a-zA-Z0-9][a-zA-Z0-9._:-]{0,127}\z}smx ? 1 : 0;
}

sub _PolicyVersionGet {
    my ($Self) = @_;

    return $Kernel::OM->Get('Kernel::Config')->Get('D724::TenantGuard::PolicyVersion') // 'unknown';
}

1;
