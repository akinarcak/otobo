# --
# CareOnCloud ESM is a web-based ticketing system for service organisations.
# --
# Copyright (C) 2001-2019 OTRS AG, https://otrs.com/
# Copyright (C) 2019-2026 Rother OSS GmbH, https://otobo.io/
# --
# This program is free software: you can redistribute it and/or modify it under
# the terms of the GNU General Public License as published by the Free Software
# Foundation, either version 3 of the License, or (at your option) any later version.
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
# You should have received a copy of the GNU General Public License
# along with this program. If not, see <https://www.gnu.org/licenses/>.
# --

package var::processes::examples::Office_Materials_Procurement_pre;

## nofilter(TidyAll::Plugin::OTOBO::Perl::PerlCritic)

use strict;
use warnings;

use parent qw(var::processes::examples::Base);

our @ObjectDependencies = ();

sub new {
    my ( $Type, %Param ) = @_;

    # allocate new hash for object
    my $Self = {%Param};
    bless( $Self, $Type );

    return $Self;
}

sub Run {
    my ( $Self, %Param ) = @_;

    # Dynamic fields definition
    my @DynamicFields = (
        {
            Name       => 'PreProcMaterialsProcurementstate',
            Label      => 'Materials Procurement State',
            FieldType  => 'Dropdown',
            ObjectType => 'Ticket',
            FieldOrder => 10000,
            Config     => {
                DefaultValue   => '',
                PossibleValues => {
                    'careoncloud5s-delivered' => 'delivered',
                    'careoncloud5s-ordered'   => 'ordered',
                },
                TranslatableValues => 0,
            },
        },
        {
            Name       => 'PreProcMaterialsProcurementItems',
            Label      => 'Materials Procurement Items',
            FieldType  => 'Multiselect',
            ObjectType => 'Ticket',
            FieldOrder => 10001,
            Config     => {
                DefaultValue   => '',
                PossibleValues => {
                    'careoncloud5s-envelope'        => 'Flipchart',
                    'careoncloud5s-flip chart'      => 'flip chart',
                    'careoncloud5s-highlighter'     => 'highlighter',
                    'careoncloud5s-hole puncher'    => 'hole puncher',
                    'careoncloud5s-labeling device' => 'labeling device',
                    'careoncloud5s-paper clip'      => 'paper clip',
                    'careoncloud5s-postits'         => 'postits',
                    'careoncloud5s-scotch tape'     => 'scotch tape',
                    'careoncloud5s-sheet protector' => 'sheet protector',
                    'careoncloud5s-stamps'          => 'stamps',
                    'careoncloud5s-staple gun'      => 'staple gun',
                    'careoncloud5s-staves'          => 'staves',
                    'careoncloud5s-storage box'     => 'storage box',
                    'careoncloud5s-toner'           => 'toner',
                    'careoncloud5s-white board'     => 'white board',
                },
                TranslatableValues => 0,
            },
        },
    );

    my %Response = $Self->DynamicFieldsAdd(
        DynamicFieldList => \@DynamicFields,
    );

    return %Response;
}

1;
