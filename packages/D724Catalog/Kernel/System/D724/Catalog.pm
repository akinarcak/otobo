# --
# D724 ESM is an enterprise service management platform based on OTOBO.
# Copyright (C) 2026 Data Market Bilgi Hizmetleri A.S.
# SPDX-License-Identifier: GPL-3.0-only
# --

package Kernel::System::D724::Catalog;

use v5.24;
use strict;
use warnings;

our $VERSION = '0.3.3';

our @ObjectDependencies = (
    'Kernel::Config',
    'Kernel::System::D724::TenantGuard',
    'Kernel::System::DB',
    'Kernel::System::JSON',
    'Kernel::System::Log',
);

my %ValidStatus = map { $_ => 1 } qw(draft active suspended retired);
my %ValidFulfillmentType = map { $_ => 1 } qw(manual process integration);
my %ValidRequestType = map { $_ => 1 } qw(service_request incident access information);
my %ValidFieldType = map { $_ => 1 } qw(text textarea select multiselect checkbox date datetime number email);

sub new {
    my ($Type) = @_;

    return bless {}, $Type;
}

sub ServiceCreate {
    my ( $Self, %Param ) = @_;
    return $Self->_Create( Entity => 'Service', %Param );
}

sub ServiceGet {
    my ( $Self, %Param ) = @_;
    return $Self->_Get( Entity => 'Service', %Param );
}

sub ServiceList {
    my ( $Self, %Param ) = @_;
    return $Self->_List( Entity => 'Service', %Param );
}

sub ServiceUpdate {
    my ( $Self, %Param ) = @_;
    return $Self->_Update( Entity => 'Service', %Param );
}

sub OfferingCreate {
    my ( $Self, %Param ) = @_;
    return $Self->_Create( Entity => 'Offering', %Param );
}

sub OfferingGet {
    my ( $Self, %Param ) = @_;
    return $Self->_Get( Entity => 'Offering', %Param );
}

sub OfferingList {
    my ( $Self, %Param ) = @_;
    return $Self->_List( Entity => 'Offering', %Param );
}

sub OfferingUpdate {
    my ( $Self, %Param ) = @_;
    return $Self->_Update( Entity => 'Offering', %Param );
}

sub CatalogItemCreate {
    my ( $Self, %Param ) = @_;
    return $Self->_Create( Entity => 'CatalogItem', %Param );
}

sub CatalogItemGet {
    my ( $Self, %Param ) = @_;
    return $Self->_Get( Entity => 'CatalogItem', %Param );
}

sub CatalogItemList {
    my ( $Self, %Param ) = @_;
    return $Self->_List( Entity => 'CatalogItem', %Param );
}

sub CatalogItemUpdate {
    my ( $Self, %Param ) = @_;
    return $Self->_Update( Entity => 'CatalogItem', %Param );
}

sub CatalogItemSchemaSet {
    my ( $Self, %Param ) = @_;

    my $Authorization = $Self->_Authorize(
        Action        => 'catalog.manage',
        RequireUserID => 1,
        Subject       => $Param{Subject},
        TenantID      => $Param{TenantID},
        UserID        => $Param{UserID},
    );
    return $Authorization if !$Authorization->{Success};
    return $Self->_Error( Error => 'ID_INVALID' )
        if !$Self->_PositiveInteger( $Param{CatalogItemID} );
    return $Self->_Error( Error => 'VERSION_REQUIRED' )
        if defined $Param{ExpectedVersion} && !$Self->_PositiveInteger( $Param{ExpectedVersion} );

    my $Item = $Self->_RowGet(
        ID       => $Param{CatalogItemID},
        Meta     => $Self->_MetaGet( Entity => 'CatalogItem' ),
        TenantID => $Param{TenantID},
    );
    return $Self->_Error( Error => 'NOT_FOUND' ) if !$Item;

    my $SchemaValidation = $Self->_SchemaValidate( Schema => $Param{Schema} );
    return $SchemaValidation if !$SchemaValidation->{Success};
    my $SchemaJSON = $Kernel::OM->Get('Kernel::System::JSON')->Encode(
        Data     => $Param{Schema},
        SortKeys => 1,
    );

    my $Current = $Self->_SchemaRowGet(
        CatalogItemID => $Param{CatalogItemID},
        TenantID      => $Param{TenantID},
    );
    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');
    if (!$Current) {
        return $Self->_Error( Error => 'VERSION_CONFLICT' )
            if defined $Param{ExpectedVersion};
        my @Values = ( $Param{TenantID}, $Param{CatalogItemID}, $SchemaJSON, $Param{UserID}, $Param{UserID} );
        my @Bind = map { \$_ } @Values;
        my $Success = $DBObject->Do(
            SQL => 'INSERT INTO d724_catalog_item_schema '
                . '(tenant_id, catalog_item_id, schema_json, version, create_time, create_by, change_time, change_by) '
                . 'VALUES (?, ?, ?, 1, current_timestamp, ?, current_timestamp, ?)',
            Bind => \@Bind,
        );
        return $Self->_Error( Error => 'DATABASE_ERROR' ) if !$Success;
    }
    else {
        return $Self->_Error( Error => 'VERSION_REQUIRED' ) if !defined $Param{ExpectedVersion};
        return $Self->_Error( Error => 'VERSION_CONFLICT' )
            if $Current->{Version} != $Param{ExpectedVersion};
        my @Values = ( $SchemaJSON, $Param{UserID}, $Param{TenantID}, $Param{CatalogItemID}, $Param{ExpectedVersion} );
        my @Bind = map { \$_ } @Values;
        my $Success = $DBObject->Do(
            SQL => 'UPDATE d724_catalog_item_schema SET schema_json = ?, version = version + 1, '
                . 'change_time = current_timestamp, change_by = ? '
                . 'WHERE tenant_id = ? AND catalog_item_id = ? AND version = ?',
            Bind => \@Bind,
        );
        return $Self->_Error( Error => 'DATABASE_ERROR' ) if !$Success;
    }

    my $Updated = $Self->_SchemaRowGet(
        CatalogItemID => $Param{CatalogItemID},
        TenantID      => $Param{TenantID},
    );
    my $Expected = $Current ? $Param{ExpectedVersion} + 1 : 1;
    return $Self->_Error( Error => 'VERSION_CONFLICT' )
        if !$Updated || $Updated->{Version} != $Expected || $Updated->{SchemaJSON} ne $SchemaJSON;
    delete $Updated->{SchemaJSON};
    $Updated->{Schema} = $Param{Schema};
    return { Success => 1, Data => $Updated };
}

sub CatalogItemSchemaGet {
    my ( $Self, %Param ) = @_;

    my $Authorization = $Self->_Authorize(
        Action   => 'catalog.read',
        Subject  => $Param{Subject},
        TenantID => $Param{TenantID},
    );
    return $Authorization if !$Authorization->{Success};
    return $Self->_Error( Error => 'ID_INVALID' )
        if !$Self->_PositiveInteger( $Param{CatalogItemID} );
    my $Current = $Self->_SchemaRowGet(
        CatalogItemID => $Param{CatalogItemID},
        TenantID      => $Param{TenantID},
    );
    return $Self->_Error( Error => 'NOT_FOUND' ) if !$Current;
    my $Schema = $Kernel::OM->Get('Kernel::System::JSON')->Decode( Data => $Current->{SchemaJSON} );
    return $Self->_Error( Error => 'SCHEMA_CORRUPT' ) if ref $Schema ne 'HASH';
    delete $Current->{SchemaJSON};
    $Current->{Schema} = $Schema;
    return { Success => 1, Data => $Current };
}

sub _Create {
    my ( $Self, %Param ) = @_;

    my $Meta = $Self->_MetaGet( Entity => $Param{Entity} );
    return $Self->_Error( Error => 'ENTITY_UNKNOWN' ) if !$Meta;

    my $Authorization = $Self->_Authorize(
        Action   => 'catalog.manage',
        RequireUserID => 1,
        Subject  => $Param{Subject},
        TenantID => $Param{TenantID},
        UserID   => $Param{UserID},
    );
    return $Authorization if !$Authorization->{Success};

    $Param{Description} //= q{};
    $Param{Status}      //= 'draft';
    $Param{ $Meta->{TypeAPI} } //= $Meta->{TypeDefault} if $Meta->{TypeAPI};

    my $Validation = $Self->_ValuesValidate(
        Meta   => $Meta,
        Param  => \%Param,
        Create => 1,
    );
    return $Validation if !$Validation->{Success};

    if ($Meta->{ParentAPI}) {
        my $ParentExists = $Self->_ParentExists(
            Meta     => $Meta,
            ParentID => $Param{ $Meta->{ParentAPI} },
            TenantID => $Param{TenantID},
        );
        return $Self->_Error( Error => 'PARENT_NOT_FOUND' ) if !$ParentExists;
    }

    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');
    $DBObject->Prepare(
        SQL   => "SELECT id FROM $Meta->{Table} WHERE tenant_id = ? AND key_name = ?",
        Bind  => [ \$Param{TenantID}, \$Param{Key} ],
        Limit => 1,
    );
    return $Self->_Error( Error => 'KEY_EXISTS' ) if $DBObject->FetchrowArray();

    my @Columns = qw(tenant_id key_name name description status version create_by change_by);
    my @Values  = (
        $Param{TenantID}, $Param{Key}, $Param{Name}, $Param{Description},
        $Param{Status}, 1, $Param{UserID}, $Param{UserID},
    );
    if ($Meta->{ParentDB}) {
        push @Columns, $Meta->{ParentDB};
        push @Values,  $Param{ $Meta->{ParentAPI} };
    }
    if ($Meta->{TypeDB}) {
        push @Columns, $Meta->{TypeDB};
        push @Values,  $Param{ $Meta->{TypeAPI} };
    }

    my @Bind;
    for my $Index ( 0 .. $#Values ) {
        push @Bind, \$Values[$Index];
    }
    my $Placeholders = join ', ', map {'?'} @Columns;
    my $Success = $DBObject->Do(
        SQL => "INSERT INTO $Meta->{Table} ("
            . join( ', ', @Columns )
            . ", create_time, change_time) VALUES ($Placeholders, current_timestamp, current_timestamp)",
        Bind => \@Bind,
    );
    return $Self->_Error( Error => 'DATABASE_ERROR' ) if !$Success;

    $DBObject->Prepare(
        SQL   => "SELECT id FROM $Meta->{Table} WHERE tenant_id = ? AND key_name = ?",
        Bind  => [ \$Param{TenantID}, \$Param{Key} ],
        Limit => 1,
    );
    my ($ID) = $DBObject->FetchrowArray();
    return $Self->_Error( Error => 'DATABASE_ERROR' ) if !$ID;

    my $Data = $Self->_RowGet(
        ID       => $ID,
        Meta     => $Meta,
        TenantID => $Param{TenantID},
    );
    return $Self->_Error( Error => 'DATABASE_ERROR' ) if !$Data;

    return {
        Success => 1,
        Data    => $Data,
    };
}

sub _Get {
    my ( $Self, %Param ) = @_;

    my $Meta = $Self->_MetaGet( Entity => $Param{Entity} );
    return $Self->_Error( Error => 'ENTITY_UNKNOWN' ) if !$Meta;

    my $Authorization = $Self->_Authorize(
        Action   => 'catalog.read',
        Subject  => $Param{Subject},
        TenantID => $Param{TenantID},
        UserID   => $Param{UserID},
    );
    return $Authorization if !$Authorization->{Success};
    return $Self->_Error( Error => 'ID_INVALID' ) if !$Self->_PositiveInteger( $Param{ $Meta->{IDAPI} } );

    my $Data = $Self->_RowGet(
        ID       => $Param{ $Meta->{IDAPI} },
        Meta     => $Meta,
        TenantID => $Param{TenantID},
    );
    return $Self->_Error( Error => 'NOT_FOUND' ) if !$Data;

    return {
        Success => 1,
        Data    => $Data,
    };
}

sub _List {
    my ( $Self, %Param ) = @_;

    my $Meta = $Self->_MetaGet( Entity => $Param{Entity} );
    return $Self->_Error( Error => 'ENTITY_UNKNOWN' ) if !$Meta;

    my $Authorization = $Self->_Authorize(
        Action       => 'catalog.read',
        RequireScope => 1,
        Subject      => $Param{Subject},
        TenantID     => $Param{TenantID},
        UserID       => $Param{UserID},
    );
    return $Authorization if !$Authorization->{Success};

    if ( defined $Param{Status} && !$ValidStatus{ $Param{Status} } ) {
        return $Self->_Error( Error => 'STATUS_INVALID' );
    }
    if ( $Meta->{ParentAPI} && defined $Param{ $Meta->{ParentAPI} } ) {
        return $Self->_Error( Error => 'PARENT_ID_INVALID' )
            if !$Self->_PositiveInteger( $Param{ $Meta->{ParentAPI} } );
    }

    my $SQL = 'SELECT ' . join( ', ', @{ $Meta->{ColumnsDB} } )
        . " FROM $Meta->{Table} WHERE tenant_id = ?";
    my @Values = ( $Param{TenantID} );
    if ( defined $Param{Status} ) {
        $SQL .= ' AND status = ?';
        push @Values, $Param{Status};
    }
    if ( $Meta->{ParentAPI} && defined $Param{ $Meta->{ParentAPI} } ) {
        $SQL .= " AND $Meta->{ParentDB} = ?";
        push @Values, $Param{ $Meta->{ParentAPI} };
    }
    $SQL .= ' ORDER BY key_name';

    my @Bind;
    for my $Index ( 0 .. $#Values ) {
        push @Bind, \$Values[$Index];
    }
    my $Limit = $Kernel::OM->Get('Kernel::Config')->Get('D724::Catalog::ListLimit') || 200;
    $Limit = 200 if $Limit !~ m{\A\d+\z}smx || $Limit < 1 || $Limit > 500;

    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');
    $DBObject->Prepare(
        SQL   => $SQL,
        Bind  => \@Bind,
        Limit => $Limit,
    );

    my @Data;
    while ( my @Row = $DBObject->FetchrowArray() ) {
        push @Data, $Self->_RowMap( Meta => $Meta, Row => \@Row );
    }

    return {
        Success => 1,
        Data    => \@Data,
    };
}

sub _Update {
    my ( $Self, %Param ) = @_;

    my $Meta = $Self->_MetaGet( Entity => $Param{Entity} );
    return $Self->_Error( Error => 'ENTITY_UNKNOWN' ) if !$Meta;

    my $Authorization = $Self->_Authorize(
        Action   => 'catalog.manage',
        RequireUserID => 1,
        Subject  => $Param{Subject},
        TenantID => $Param{TenantID},
        UserID   => $Param{UserID},
    );
    return $Authorization if !$Authorization->{Success};
    return $Self->_Error( Error => 'ID_INVALID' ) if !$Self->_PositiveInteger( $Param{ $Meta->{IDAPI} } );
    return $Self->_Error( Error => 'VERSION_REQUIRED' ) if !$Self->_PositiveInteger( $Param{ExpectedVersion} );

    my $Current = $Self->_RowGet(
        ID       => $Param{ $Meta->{IDAPI} },
        Meta     => $Meta,
        TenantID => $Param{TenantID},
    );
    return $Self->_Error( Error => 'NOT_FOUND' ) if !$Current;
    return $Self->_Error( Error => 'VERSION_CONFLICT' )
        if $Current->{Version} != $Param{ExpectedVersion};

    for my $Field (qw(Name Description Status)) {
        $Param{$Field} = $Current->{$Field} if !defined $Param{$Field};
    }
    if ($Meta->{ParentAPI}) {
        return $Self->_Error( Error => 'PARENT_IMMUTABLE' )
            if defined $Param{ $Meta->{ParentAPI} }
            && $Param{ $Meta->{ParentAPI} } != $Current->{ $Meta->{ParentAPI} };
        $Param{ $Meta->{ParentAPI} } = $Current->{ $Meta->{ParentAPI} };
    }
    if ($Meta->{TypeAPI}) {
        $Param{ $Meta->{TypeAPI} } = $Current->{ $Meta->{TypeAPI} }
            if !defined $Param{ $Meta->{TypeAPI} };
    }
    my $Validation = $Self->_ValuesValidate(
        Meta  => $Meta,
        Param => \%Param,
    );
    return $Validation if !$Validation->{Success};

    my @SetColumns = qw(name description status);
    my @Values     = ( $Param{Name}, $Param{Description}, $Param{Status} );
    if ($Meta->{TypeDB}) {
        push @SetColumns, $Meta->{TypeDB};
        push @Values,     $Param{ $Meta->{TypeAPI} };
    }
    my $SetSQL = join ', ', map { "$SetColumns[$_] = ?" } 0 .. $#SetColumns;
    push @Values, $Param{UserID}, $Param{ $Meta->{IDAPI} }, $Param{TenantID}, $Param{ExpectedVersion};

    my @Bind;
    for my $Index ( 0 .. $#Values ) {
        push @Bind, \$Values[$Index];
    }
    my $Success = $Kernel::OM->Get('Kernel::System::DB')->Do(
        SQL => "UPDATE $Meta->{Table} SET $SetSQL, version = version + 1, "
            . 'change_time = current_timestamp, change_by = ? '
            . 'WHERE id = ? AND tenant_id = ? AND version = ?',
        Bind => \@Bind,
    );
    return $Self->_Error( Error => 'DATABASE_ERROR' ) if !$Success;

    my $Updated = $Self->_RowGet(
        ID       => $Param{ $Meta->{IDAPI} },
        Meta     => $Meta,
        TenantID => $Param{TenantID},
    );
    return $Self->_Error( Error => 'VERSION_CONFLICT' )
        if !$Updated || $Updated->{Version} != $Param{ExpectedVersion} + 1;
    for my $Field (qw(Name Description Status)) {
        return $Self->_Error( Error => 'VERSION_CONFLICT' ) if $Updated->{$Field} ne $Param{$Field};
    }
    if ($Meta->{TypeAPI}) {
        return $Self->_Error( Error => 'VERSION_CONFLICT' )
            if $Updated->{ $Meta->{TypeAPI} } ne $Param{ $Meta->{TypeAPI} };
    }

    return {
        Success => 1,
        Data    => $Updated,
    };
}

sub _Authorize {
    my ( $Self, %Param ) = @_;

    return $Self->_Error( Error => 'CATALOG_DISABLED' )
        if !$Kernel::OM->Get('Kernel::Config')->Get('D724::Catalog::Enabled');
    return $Self->_Error( Error => 'USER_ID_INVALID' )
        if $Param{RequireUserID} && !$Self->_PositiveInteger( $Param{UserID} );

    my $Guard = $Kernel::OM->Get('Kernel::System::D724::TenantGuard');
    if ($Param{RequireScope}) {
        my $Scope = $Guard->ScopeGet( Subject => $Param{Subject} );
        return $Self->_Error(
            Error  => 'FORBIDDEN',
            Reason => $Scope->{Reason},
        ) if !$Scope->{Success};

        my %TenantScope = map { $_ => 1 } @{ $Scope->{TenantIDs} };
        return $Self->_Error(
            Error  => 'FORBIDDEN',
            Reason => 'DENY_CROSS_TENANT',
        ) if !$Scope->{Unrestricted} && !$TenantScope{ $Param{TenantID} // q{} };
    }

    my $Decision = $Guard->DecisionGet(
        Action   => $Param{Action},
        Subject  => $Param{Subject},
        Resource => { TenantID => $Param{TenantID} },
    );
    return $Self->_Error(
        Error  => 'FORBIDDEN',
        Reason => $Decision->{Reason},
    ) if !$Decision->{Allowed};

    return { Success => 1 };
}

sub _ValuesValidate {
    my ( $Self, %Param ) = @_;

    my $Values = $Param{Param};
    return $Self->_Error( Error => 'KEY_INVALID' )
        if $Param{Create}
        && ( !defined $Values->{Key} || $Values->{Key} !~ m{\A[a-z0-9][a-z0-9._-]{0,99}\z}smx );
    return $Self->_Error( Error => 'NAME_INVALID' )
        if !defined $Values->{Name}
        || !length $Values->{Name}
        || length $Values->{Name} > 200
        || $Values->{Name} =~ m{[\x00-\x1f]}smx;
    return $Self->_Error( Error => 'DESCRIPTION_INVALID' )
        if !defined $Values->{Description} || length $Values->{Description} > 4000;
    return $Self->_Error( Error => 'STATUS_INVALID' ) if !$ValidStatus{ $Values->{Status} // q{} };

    my $Meta = $Param{Meta};
    if ($Meta->{ParentAPI}) {
        return $Self->_Error( Error => 'PARENT_ID_INVALID' )
            if !$Self->_PositiveInteger( $Values->{ $Meta->{ParentAPI} } );
    }
    if ( $Meta->{TypeAPI} && $Meta->{TypeAPI} eq 'FulfillmentType' ) {
        return $Self->_Error( Error => 'FULFILLMENT_TYPE_INVALID' )
            if !$ValidFulfillmentType{ $Values->{FulfillmentType} // q{} };
    }
    if ( $Meta->{TypeAPI} && $Meta->{TypeAPI} eq 'RequestType' ) {
        return $Self->_Error( Error => 'REQUEST_TYPE_INVALID' )
            if !$ValidRequestType{ $Values->{RequestType} // q{} };
    }

    return { Success => 1 };
}

sub _ParentExists {
    my ( $Self, %Param ) = @_;

    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');
    $DBObject->Prepare(
        SQL   => "SELECT id FROM $Param{Meta}->{ParentTable} WHERE id = ? AND tenant_id = ?",
        Bind  => [ \$Param{ParentID}, \$Param{TenantID} ],
        Limit => 1,
    );
    my ($ID) = $DBObject->FetchrowArray();
    return $ID ? 1 : 0;
}

sub _SchemaValidate {
    my ( $Self, %Param ) = @_;

    my $Schema = $Param{Schema};
    return $Self->_Error( Error => 'SCHEMA_INVALID' ) if ref $Schema ne 'HASH';
    return $Self->_Error( Error => 'SCHEMA_VERSION_INVALID' )
        if !$Self->_PositiveInteger( $Schema->{version} );
    return $Self->_Error( Error => 'SCHEMA_FIELDS_INVALID' )
        if ref $Schema->{fields} ne 'ARRAY' || @{ $Schema->{fields} } > 50;
    my %TopLevelAllowed = map { $_ => 1 } qw(version fields workflow);
    for my $Key ( keys %{$Schema} ) {
        return $Self->_Error( Error => 'SCHEMA_PROPERTY_UNKNOWN' ) if !$TopLevelAllowed{$Key};
    }
    my %Keys;
    for my $Field ( @{ $Schema->{fields} } ) {
        return $Self->_Error( Error => 'SCHEMA_FIELD_INVALID' ) if ref $Field ne 'HASH';
        return $Self->_Error( Error => 'SCHEMA_FIELD_KEY_INVALID' )
            if !defined $Field->{key} || $Field->{key} !~ m{\A[a-z][a-z0-9_]{0,63}\z}smx || $Keys{ $Field->{key} }++;
        return $Self->_Error( Error => 'SCHEMA_FIELD_LABEL_INVALID' )
            if !defined $Field->{label} || !length $Field->{label} || length $Field->{label} > 200;
        return $Self->_Error( Error => 'SCHEMA_FIELD_TYPE_INVALID' )
            if !$ValidFieldType{ $Field->{type} // q{} };
        return $Self->_Error( Error => 'SCHEMA_FIELD_REQUIRED_INVALID' )
            if defined $Field->{required} && $Field->{required} !~ m{\A[01]\z}smx;
        if ( $Field->{type} eq 'select' || $Field->{type} eq 'multiselect' ) {
            return $Self->_Error( Error => 'SCHEMA_FIELD_OPTIONS_INVALID' )
                if ref $Field->{options} ne 'ARRAY' || !@{ $Field->{options} } || @{ $Field->{options} } > 100;
            my %OptionValues;
            for my $Option ( @{ $Field->{options} } ) {
                return $Self->_Error( Error => 'SCHEMA_FIELD_OPTIONS_INVALID' )
                    if ref $Option ne 'HASH'
                    || !defined $Option->{value} || $Option->{value} !~ m{\A[a-zA-Z0-9][a-zA-Z0-9._:-]{0,99}\z}smx
                    || !defined $Option->{label} || !length $Option->{label} || length $Option->{label} > 200
                    || $OptionValues{ $Option->{value} }++;
            }
        }
        elsif ( exists $Field->{options} ) {
            return $Self->_Error( Error => 'SCHEMA_FIELD_OPTIONS_INVALID' );
        }
    }
    if ( defined $Schema->{workflow} ) {
        my $Workflow = $Schema->{workflow};
        return $Self->_Error( Error => 'SCHEMA_WORKFLOW_INVALID' ) if ref $Workflow ne 'HASH';
        my %WorkflowAllowed = map { $_ => 1 } qw(approval fulfillment);
        for my $Key ( keys %{$Workflow} ) {
            return $Self->_Error( Error => 'SCHEMA_WORKFLOW_PROPERTY_UNKNOWN' ) if !$WorkflowAllowed{$Key};
        }
        if ( defined $Workflow->{approval} ) {
            my $Approval = $Workflow->{approval};
            return $Self->_Error( Error => 'SCHEMA_APPROVAL_INVALID' )
                if ref $Approval ne 'HASH'
                || !defined $Approval->{required}
                || $Approval->{required} !~ m{\A[01]\z}smx
                || ( $Approval->{required} && ( $Approval->{approver_role} // q{} ) !~ m{\A(?:tenant_admin|service_owner)\z}smx );
        }
        if ( defined $Workflow->{fulfillment} ) {
            my $Tasks = $Workflow->{fulfillment};
            return $Self->_Error( Error => 'SCHEMA_FULFILLMENT_INVALID' )
                if ref $Tasks ne 'ARRAY' || !@{$Tasks} || @{$Tasks} > 20;
            my %TaskKeys;
            for my $Task ( @{$Tasks} ) {
                my %TaskAllowed = map { $_ => 1 } qw(key name type);
                return $Self->_Error( Error => 'SCHEMA_FULFILLMENT_INVALID' )
                    if ref $Task ne 'HASH'
                    || ( grep { !$TaskAllowed{$_} } keys %{$Task} )
                    || ( $Task->{key} // q{} ) !~ m{\A[a-z][a-z0-9_-]{0,63}\z}smx
                    || $TaskKeys{ $Task->{key} }++
                    || !length( $Task->{name} // q{} ) || length $Task->{name} > 200
                    || ( $Task->{type} // q{} ) !~ m{\A(?:manual|process|integration)\z}smx;
            }
        }
    }
    return { Success => 1 };
}

sub _SchemaRowGet {
    my ( $Self, %Param ) = @_;

    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');
    $DBObject->Prepare(
        SQL => 'SELECT catalog_item_id, tenant_id, schema_json, version, create_time, create_by, change_time, change_by '
            . 'FROM d724_catalog_item_schema WHERE catalog_item_id = ? AND tenant_id = ?',
        Bind  => [ \$Param{CatalogItemID}, \$Param{TenantID} ],
        Limit => 1,
    );
    my @Row = $DBObject->FetchrowArray();
    return if !@Row;
    my @Columns = qw(CatalogItemID TenantID SchemaJSON Version CreateTime CreateBy ChangeTime ChangeBy);
    my %Data;
    @Data{@Columns} = @Row;
    return \%Data;
}

sub _RowGet {
    my ( $Self, %Param ) = @_;

    my $Meta     = $Param{Meta};
    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');
    $DBObject->Prepare(
        SQL => 'SELECT ' . join( ', ', @{ $Meta->{ColumnsDB} } )
            . " FROM $Meta->{Table} WHERE id = ? AND tenant_id = ?",
        Bind  => [ \$Param{ID}, \$Param{TenantID} ],
        Limit => 1,
    );
    my @Row = $DBObject->FetchrowArray();
    return if !@Row;

    return $Self->_RowMap( Meta => $Meta, Row => \@Row );
}

sub _RowMap {
    my ( $Self, %Param ) = @_;

    my %Data;
    my $ColumnsAPI = $Param{Meta}->{ColumnsAPI};
    for my $Index ( 0 .. $#{$ColumnsAPI} ) {
        $Data{ $ColumnsAPI->[$Index] } = $Param{Row}->[$Index];
    }
    return \%Data;
}

sub _MetaGet {
    my ( $Self, %Param ) = @_;

    my %Meta = (
        Service => {
            Table      => 'd724_service',
            IDAPI      => 'ServiceID',
            ColumnsDB  => [qw(id tenant_id key_name name description status version create_time create_by change_time change_by)],
            ColumnsAPI => [qw(ServiceID TenantID Key Name Description Status Version CreateTime CreateBy ChangeTime ChangeBy)],
        },
        Offering => {
            Table       => 'd724_service_offering',
            IDAPI       => 'OfferingID',
            ParentAPI   => 'ServiceID',
            ParentDB    => 'service_id',
            ParentTable => 'd724_service',
            TypeAPI     => 'FulfillmentType',
            TypeDB      => 'fulfillment_type',
            TypeDefault => 'manual',
            ColumnsDB   => [qw(id tenant_id service_id key_name name description status fulfillment_type version create_time create_by change_time change_by)],
            ColumnsAPI  => [qw(OfferingID TenantID ServiceID Key Name Description Status FulfillmentType Version CreateTime CreateBy ChangeTime ChangeBy)],
        },
        CatalogItem => {
            Table       => 'd724_catalog_item',
            IDAPI       => 'CatalogItemID',
            ParentAPI   => 'OfferingID',
            ParentDB    => 'offering_id',
            ParentTable => 'd724_service_offering',
            TypeAPI     => 'RequestType',
            TypeDB      => 'request_type',
            TypeDefault => 'service_request',
            ColumnsDB   => [qw(id tenant_id offering_id key_name name description status request_type version create_time create_by change_time change_by)],
            ColumnsAPI  => [qw(CatalogItemID TenantID OfferingID Key Name Description Status RequestType Version CreateTime CreateBy ChangeTime ChangeBy)],
        },
    );

    return $Meta{ $Param{Entity} };
}

sub _PositiveInteger {
    my ( $Self, $Value ) = @_;
    return defined $Value && $Value =~ m{\A[1-9][0-9]*\z}smx ? 1 : 0;
}

sub _Error {
    my ( $Self, %Param ) = @_;
    my $Error = {
        Success => 0,
        Error   => $Param{Error} // 'UNKNOWN_ERROR',
    };
    $Error->{Reason} = $Param{Reason} if defined $Param{Reason};
    return $Error;
}

1;
