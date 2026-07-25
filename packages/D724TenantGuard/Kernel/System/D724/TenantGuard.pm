# --
# D724 ESM is an enterprise service management platform based on OTOBO.
# Copyright (C) 2026 Data Market Bilgi Hizmetleri A.S.
# SPDX-License-Identifier: GPL-3.0-only
# --

package Kernel::System::D724::TenantGuard;

use v5.24;
use strict;
use warnings;

our $VERSION = '0.10.0';

our @ObjectDependencies = (
    'Kernel::Config',
    'Kernel::System::DB',
);

my %RoleActions = (
    requester => {
        map { $_ => 1 } qw(catalog.read case.create case.read case.comment search.read integration.ticket.get integration.ticket.history)
    },
    agent => {
        map { $_ => 1 } qw(catalog.read case.create case.read case.comment case.update case.assign cmdb.read search.read integration.ticket.get integration.ticket.history integration.ticket.update)
    },
    service_owner => {
        map { $_ => 1 } qw(catalog.read catalog.manage case.create case.read case.comment case.update case.assign case.delete audit.read cmdb.read report.read report.export search.read integration.ticket.get integration.ticket.history integration.ticket.update)
    },
    auditor => {
        map { $_ => 1 } qw(catalog.read case.read audit.read cmdb.read report.read report.export search.read integration.ticket.get integration.ticket.history)
    },
    automation => {
        map { $_ => 1 } qw(catalog.read case.create case.read case.comment case.update case.assign automation.execute cmdb.read search.read integration.ticket.get integration.ticket.history integration.ticket.update)
    },
    tenant_admin => {
        map { $_ => 1 } qw(catalog.read catalog.manage case.create case.read case.comment case.update case.assign case.delete audit.read tenant.manage identity.manage scim.provision automation.execute cmdb.read cmdb.manage report.read report.export search.read integration.ticket.get integration.ticket.history integration.ticket.update)
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

    my $Roles        = $Subject->{Roles};
    my $RoleBindings = $Subject->{RoleBindings};
    return $Deny->('DENY_SUBJECT_ROLES_MISSING')
        if ref $RoleBindings ne 'HASH' && ( ref $Roles ne 'ARRAY' || !@{$Roles} );
    return $Deny->('DENY_ROLE_BINDINGS_EMPTY')
        if ref $RoleBindings eq 'HASH' && !keys %{$RoleBindings};

    my $SubjectTenantIDs = ref $RoleBindings eq 'HASH'
        ? [ keys %{$RoleBindings} ]
        : $Subject->{TenantIDs};
    return $Deny->('DENY_SUBJECT_TENANT_MISSING') if ref $SubjectTenantIDs ne 'ARRAY' || !@{$SubjectTenantIDs};
    for my $TenantID ( @{$SubjectTenantIDs} ) {
        return $Deny->('DENY_TENANT_IDENTIFIER_INVALID') if !$Self->_IdentifierValid($TenantID);
        return $Deny->('DENY_ROLE_BINDING_INVALID')
            if ref $RoleBindings eq 'HASH'
            && ( ref $RoleBindings->{$TenantID} ne 'ARRAY' || !@{ $RoleBindings->{$TenantID} } );
    }
    if ( ref $RoleBindings eq 'HASH' && defined $Subject->{TenantIDs} ) {
        return $Deny->('DENY_TENANT_SCOPE_MISMATCH') if ref $Subject->{TenantIDs} ne 'ARRAY';
        my %Declared = map { $_ => 1 } @{ $Subject->{TenantIDs} };
        my %Bound    = map { $_ => 1 } keys %{$RoleBindings};
        return $Deny->('DENY_TENANT_SCOPE_MISMATCH')
            if join( q{|}, sort keys %Declared ) ne join( q{|}, sort keys %Bound );
    }

    my $Resource = $Param{Resource};
    return $Deny->('DENY_RESOURCE_MISSING') if ref $Resource ne 'HASH';
    return $Deny->('DENY_RESOURCE_TENANT_MISSING')
        if !defined $Resource->{TenantID} || !length $Resource->{TenantID};
    return $Deny->('DENY_TENANT_IDENTIFIER_INVALID')
        if !$Self->_IdentifierValid( $Resource->{TenantID} );

    my %Roles;
    %Roles = map { $_ => 1 } @{$Roles} if ref $Roles eq 'ARRAY';
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

    my $ResourceRoles = ref $RoleBindings eq 'HASH'
        ? $RoleBindings->{ $Resource->{TenantID} }
        : $Roles;
    for my $Role ( @{ $ResourceRoles // [] } ) {
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

    my $Roles        = $Subject->{Roles};
    my $RoleBindings = $Subject->{RoleBindings};
    return {
        Success       => 0,
        Reason        => 'DENY_SUBJECT_ROLES_MISSING',
        PolicyVersion => $PolicyVersion,
        TenantIDs     => [],
    } if ref $RoleBindings ne 'HASH' && ( ref $Roles ne 'ARRAY' || !@{$Roles} );

    return {
        Success       => 0,
        Reason        => 'DENY_ROLE_BINDINGS_EMPTY',
        PolicyVersion => $PolicyVersion,
        TenantIDs     => [],
    } if ref $RoleBindings eq 'HASH' && !keys %{$RoleBindings};

    my %Roles;
    %Roles = map { $_ => 1 } @{$Roles} if ref $Roles eq 'ARRAY';
    my $KnownRole = $Roles{platform_admin};
    for my $Role ( keys %Roles ) {
        $KnownRole = 1 if $RoleActions{$Role};
    }
    if ( ref $RoleBindings eq 'HASH' ) {
        for my $TenantID ( keys %{$RoleBindings} ) {
            my $TenantRoles = $RoleBindings->{$TenantID};
            next if ref $TenantRoles ne 'ARRAY';
            for my $Role ( @{$TenantRoles} ) {
                $KnownRole = 1 if $RoleActions{$Role};
            }
        }
    }
    return {
        Success       => 0,
        Reason        => 'DENY_ROLE_NOT_GRANTED',
        PolicyVersion => $PolicyVersion,
        TenantIDs     => [],
    } if !$KnownRole;

    my $TenantIDs = ref $RoleBindings eq 'HASH' ? [ keys %{$RoleBindings} ] : $Subject->{TenantIDs};
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
        return {
            Success       => 0,
            Reason        => 'DENY_ROLE_BINDING_INVALID',
            PolicyVersion => $PolicyVersion,
            TenantIDs     => [],
        } if ref $RoleBindings eq 'HASH'
            && ( ref $RoleBindings->{$TenantID} ne 'ARRAY' || !@{ $RoleBindings->{$TenantID} } );
        $TenantIDs{$TenantID} = 1;
    }
    if ( ref $RoleBindings eq 'HASH' && defined $Subject->{TenantIDs} ) {
        return {
            Success       => 0,
            Reason        => 'DENY_TENANT_SCOPE_MISMATCH',
            PolicyVersion => $PolicyVersion,
            TenantIDs     => [],
        } if ref $Subject->{TenantIDs} ne 'ARRAY';
        my %Declared = map { $_ => 1 } @{ $Subject->{TenantIDs} };
        return {
            Success       => 0,
            Reason        => 'DENY_TENANT_SCOPE_MISMATCH',
            PolicyVersion => $PolicyVersion,
            TenantIDs     => [],
        } if join( q{|}, sort keys %Declared ) ne join( q{|}, sort keys %TenantIDs );
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

sub AutomationAuthorize {
    my ( $Self, %Param ) = @_;

    my $TenantID = $Param{TenantID};
    return { Success => 0, Error => 'TENANT_ID_INVALID', Reason => 'DENY_TENANT_IDENTIFIER_INVALID' }
        if !$Self->_IdentifierValid($TenantID);
    return { Success => 0, Error => 'JOB_NAME_INVALID', Reason => 'DENY_SUBJECT_ID_MISSING' }
        if ( $Param{JobName} // q{} ) !~ m{\A[a-zA-Z0-9][a-zA-Z0-9_.:-]{0,63}\z}smx;

    my $DB = $Kernel::OM->Get('Kernel::System::DB');
    return { Success => 0, Error => 'TENANT_LOOKUP_FAILED', Reason => 'DENY_POLICY_ERROR' }
        if !$DB->Prepare(
            SQL => "SELECT 1 FROM d724_tenant WHERE key_name = ? AND status = 'active'",
            Bind => [ \$TenantID ], Limit => 1,
        );
    my ($Active) = $DB->FetchrowArray();
    return { Success => 0, Error => 'TENANT_INACTIVE', Reason => 'DENY_TENANT_INACTIVE' } if !$Active;

    my $Subject = {
        ID => "automation:$Param{JobName}", TenantIDs => [$TenantID],
        RoleBindings => { $TenantID => ['automation'] },
    };
    my $Decision = $Self->DecisionGet(
        Subject => $Subject, Resource => { TenantID => $TenantID }, Action => 'automation.execute',
    );
    return {
        Success => 0, Error => 'AUTOMATION_FORBIDDEN', Reason => $Decision->{Reason},
        PolicyVersion => $Decision->{PolicyVersion},
    } if !$Decision->{Allowed};
    return {
        Success => 1, Subject => $Subject, Reason => $Decision->{Reason},
        PolicyVersion => $Decision->{PolicyVersion},
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
