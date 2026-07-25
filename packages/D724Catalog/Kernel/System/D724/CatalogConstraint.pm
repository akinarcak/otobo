# --
# Copyright (C) 2026 Data Market Bilgi Hizmetleri A.S.
# SPDX-License-Identifier: GPL-3.0-only
# --
package Kernel::System::D724::CatalogConstraint;

use v5.24;
use strict;
use warnings;

our $VERSION = '0.6.1';
our @ObjectDependencies = ('Kernel::System::DB');

my @Constraint = (
    { Name => 'd724_fk_offering_service_tenant', Table => 'd724_service_offering', Columns => [qw(tenant_id service_id)], ForeignTable => 'd724_service', ForeignColumns => [qw(tenant_id id)] },
    { Name => 'd724_fk_item_offering_tenant', Table => 'd724_catalog_item', Columns => [qw(tenant_id offering_id)], ForeignTable => 'd724_service_offering', ForeignColumns => [qw(tenant_id id)] },
    { Name => 'd724_fk_schema_item_tenant', Table => 'd724_catalog_item_schema', Columns => [qw(tenant_id catalog_item_id)], ForeignTable => 'd724_catalog_item', ForeignColumns => [qw(tenant_id id)] },
);

sub new { return bless {}, $_[0] }

sub Ensure {
    my ($Self) = @_;
    my $DB = $Kernel::OM->Get('Kernel::System::DB');
    my $Status = $Self->StatusGet();

    if ( !$Status->{UniqueItemTenantID} ) {
        return { Success => 0, Error => 'UNIQUE_INDEX_CREATE_FAILED' } if !$DB->Do(
            SQL => 'ALTER TABLE d724_catalog_item ADD UNIQUE INDEX d724_item_tenant_id (tenant_id, id)',
        );
    }
    for my $Constraint (@Constraint) {
        next if $Status->{Constraints}->{ $Constraint->{Name} };
        my $SQL = sprintf 'ALTER TABLE %s ADD CONSTRAINT %s FOREIGN KEY (%s) REFERENCES %s (%s)',
            $Constraint->{Table}, $Constraint->{Name}, join( ', ', @{ $Constraint->{Columns} } ),
            $Constraint->{ForeignTable}, join( ', ', @{ $Constraint->{ForeignColumns} } );
        return { Success => 0, Error => 'CONSTRAINT_CREATE_FAILED', Constraint => $Constraint->{Name} }
            if !$DB->Do( SQL => $SQL );
    }
    return $Self->StatusGet();
}

sub StatusGet {
    my ($Self) = @_;
    my $DB = $Kernel::OM->Get('Kernel::System::DB');
    my %Found;
    $DB->Prepare(
        SQL => 'SELECT constraint_name, table_name, column_name, referenced_table_name, referenced_column_name, ordinal_position '
            . 'FROM information_schema.key_column_usage WHERE table_schema = DATABASE() '
            . q{AND table_name IN ('d724_service_offering','d724_catalog_item','d724_catalog_item_schema') }
            . 'AND referenced_table_name IS NOT NULL ORDER BY constraint_name, ordinal_position',
    );
    while ( my @Row = $DB->FetchrowArray() ) {
        push @{ $Found{ $Row[0] } }, { Table => $Row[1], Column => $Row[2], ForeignTable => $Row[3], ForeignColumn => $Row[4] };
    }

    my %Valid;
    for my $Constraint (@Constraint) {
        my $Rows = $Found{ $Constraint->{Name} } // [];
        my $Signature = join '|', map { "$_->{Table}.$_->{Column}>$_->{ForeignTable}.$_->{ForeignColumn}" } @{$Rows};
        my @Expected;
        for my $Index ( 0 .. $#{ $Constraint->{Columns} } ) {
            push @Expected, $Constraint->{Table} . '.' . $Constraint->{Columns}->[$Index] . '>'
                . $Constraint->{ForeignTable} . '.' . $Constraint->{ForeignColumns}->[$Index];
        }
        $Valid{ $Constraint->{Name} } = $Signature eq join( '|', @Expected ) ? 1 : 0;
    }

    $DB->Prepare(
        SQL => q{SELECT COUNT(*) FROM information_schema.statistics WHERE table_schema = DATABASE() }
            . q{AND table_name = 'd724_catalog_item' AND index_name = 'd724_item_tenant_id' AND non_unique = 0},
    );
    my ($Unique) = $DB->FetchrowArray();
    my $Success = $Unique && !grep { !$Valid{$_} } keys %Valid;
    return { Success => $Success ? 1 : 0, UniqueItemTenantID => $Unique ? 1 : 0, Constraints => \%Valid };
}

1;
