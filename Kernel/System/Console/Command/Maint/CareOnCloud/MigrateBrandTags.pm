# --
# CareOnCloud ESM is a web-based ticketing system for service organisations.
# --
# Copyright (C) 2001-2020 OTRS AG, https://otrs.com/
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

package Kernel::System::Console::Command::Maint::CareOnCloud::MigrateBrandTags;

use strict;
use warnings;

use parent qw(Kernel::System::Console::BaseCommand);

our @ObjectDependencies = (
    'Kernel::System::DB',
    'Kernel::System::Encode',
);

=head1 NAME

Kernel::System::Console::Command::Maint::CareOnCloud::MigrateBrandTags - rewrite
stored legacy brand identifiers

=head1 DESCRIPTION

The template smart tags, the PostMaster header names and a few XML container keys
were renamed from the legacy product name to CareOnCloud. Those identifiers do not
only live in the source tree, they are also stored inside database rows that users
have edited: notification bodies, auto responses, salutations, signatures,
templates, PostMaster filters and modified SysConfig values.

This command rewrites them. It reports what it would change and does nothing
unless C<--execute> is given.

After a successful run rebuild the configuration:

    bin/careoncloud.Console.pl Maint::Config::Rebuild

=cut

# Ordered: the longest token first, so no replacement can consume a prefix of
# another one.
my @Replacements = (
    [ 'X-OTOBO-'       => 'X-CareOnCloud-' ],
    [ 'OTOBO_'         => 'CareOnCloud_' ],
    [ 'otobo_infotile' => 'careoncloud_infotile' ],
    [ 'otobo_stats'    => 'careoncloud_stats' ],
);

# Tables whose rows carry the identifiers. Each entry lists the primary key
# columns used to address a row and the columns that are rewritten.
my @Tables = (
    {
        Table   => 'notification_event_message',
        Key     => ['id'],
        Columns => [ 'subject', 'text' ],
    },
    {
        Table   => 'auto_response',
        Key     => ['id'],
        Columns => [ 'text0', 'text1' ],
    },
    {
        Table   => 'salutation',
        Key     => ['id'],
        Columns => ['text'],
    },
    {
        Table   => 'signature',
        Key     => ['id'],
        Columns => ['text'],
    },
    {
        Table   => 'standard_template',
        Key     => ['id'],
        Columns => ['text'],
    },
    {
        Table   => 'postmaster_filter',
        Key     => [ 'f_name', 'f_type', 'f_key', 'f_value' ],
        Columns => [ 'f_key', 'f_value' ],
    },
    {
        Table   => 'sysconfig_modified',
        Key     => ['id'],
        Columns => ['effective_value'],
    },
    {
        Table   => 'xml_storage',
        Key     => [ 'xml_type', 'xml_key', 'xml_content_key' ],
        Columns => [ 'xml_content_key', 'xml_content_value' ],
    },
);

sub Configure {
    my ( $Self, %Param ) = @_;

    $Self->Description('Rewrite legacy brand identifiers stored in the database.');
    $Self->AddOption(
        Name        => 'execute',
        Description => 'Actually write the changes. Without it the command only reports.',
        Required    => 0,
        HasValue    => 0,
    );

    return;
}

sub Run {
    my ( $Self, %Param ) = @_;

    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');
    my $Execute  = $Self->GetOption('execute') ? 1 : 0;

    if ( !$Execute ) {
        $Self->Print("<yellow>Dry run. Pass --execute to write the changes.</yellow>\n\n");
    }

    my $TotalRows   = 0;
    my $TotalValues = 0;

    TABLE:
    for my $Entry (@Tables) {
        my $Table   = $Entry->{Table};
        my @Key     = @{ $Entry->{Key} };
        my @Columns = @{ $Entry->{Columns} };

        my $SQL = 'SELECT ' . join( ', ', @Key, @Columns ) . " FROM $Table";

        if ( !$DBObject->Prepare( SQL => $SQL ) ) {
            $Self->PrintError("Could not read $Table.\n");
            return $Self->ExitCodeError();
        }

        # Collect first: the same handle cannot be used for the UPDATE below.
        my @Rows;
        while ( my @Data = $DBObject->FetchrowArray() ) {
            push @Rows, \@Data;
        }

        my $TableRows   = 0;
        my $TableValues = 0;

        ROW:
        for my $Row (@Rows) {
            my @KeyValues = @{$Row}[ 0 .. $#Key ];
            my @Values    = @{$Row}[ scalar(@Key) .. $#{$Row} ];

            my @NewValues;
            my $RowChanged = 0;

            VALUE:
            for my $Value (@Values) {
                if ( !defined $Value ) {
                    push @NewValues, $Value;
                    next VALUE;
                }

                my $New = $Value;
                for my $Pair (@Replacements) {
                    my ( $From, $To ) = @{$Pair};
                    $New =~ s{\Q$From\E}{$To}g;
                }

                if ( $New ne $Value ) {
                    $RowChanged = 1;
                    $TableValues++;
                }

                push @NewValues, $New;
            }

            next ROW if !$RowChanged;
            $TableRows++;

            next ROW if !$Execute;

            my $UpdateSQL = "UPDATE $Table SET "
                . join( ', ', map {"$_ = ?"} @Columns )
                . ' WHERE '
                . join( ' AND ', map {"$_ = ?"} @Key );

            my @Bind = ( ( map { \$_ } @NewValues ), ( map { \$_ } @KeyValues ) );

            if ( !$DBObject->Do( SQL => $UpdateSQL, Bind => \@Bind ) ) {
                $Self->PrintError("Could not update $Table.\n");
                return $Self->ExitCodeError();
            }
        }

        $TotalRows   += $TableRows;
        $TotalValues += $TableValues;

        if ($TableRows) {
            $Self->Print("  <green>$Table</green>: $TableRows row(s), $TableValues value(s)\n");
        }
        else {
            $Self->Print("  $Table: nothing to do\n");
        }
    }

    $Self->Print("\n$TotalValues value(s) in $TotalRows row(s)");
    $Self->Print( $Execute ? " <green>updated</green>.\n" : " <yellow>would be updated</yellow>.\n" );

    if ( $Execute && $TotalRows ) {
        $Self->Print("\n<yellow>Now run: bin/careoncloud.Console.pl Maint::Config::Rebuild</yellow>\n");
    }

    return $Self->ExitCodeOk();
}

1;
