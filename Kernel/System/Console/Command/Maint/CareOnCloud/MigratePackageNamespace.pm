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

package Kernel::System::Console::Command::Maint::CareOnCloud::MigratePackageNamespace;

use strict;
use warnings;

use parent qw(Kernel::System::Console::BaseCommand);

our @ObjectDependencies = (
    'Kernel::System::Cache',
    'Kernel::System::DB',
);

=head1 NAME

Kernel::System::Console::Command::Maint::CareOnCloud::MigratePackageNamespace - move
the D724 namespace to CareOnCloud

=head1 DESCRIPTION

The product packages were developed under the working name D724 and that name
reached the database in three places: the tables they create, the SysConfig
settings they register and their own entries in the package repository.

This command moves all three. It deliberately never uninstalls a package,
because C<DatabaseUninstall> would drop the tables and their data; the rows are
rewritten in place instead.

Run it while the web and daemon processes are stopped, then rebuild:

    bin/careoncloud.Console.pl Maint::Config::Rebuild

=cut

sub Configure {
    my ( $Self, %Param ) = @_;

    $Self->Description('Move the D724 namespace to CareOnCloud, keeping all data.');
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

    # -----------------------------------------------------------------------
    # 1. tables
    # -----------------------------------------------------------------------
    return $Self->ExitCodeError() if !$DBObject->Prepare(
        SQL => "SELECT table_name FROM information_schema.tables"
            . " WHERE table_schema = DATABASE() AND table_name LIKE 'd724\\_%'"
            . " ORDER BY table_name",
    );

    my @Tables;
    while ( my @Row = $DBObject->FetchrowArray() ) {
        push @Tables, $Row[0];
    }

    $Self->Print("Tables to rename: " . scalar(@Tables) . "\n");

    TABLE:
    for my $Table (@Tables) {
        my $New = $Table;
        $New =~ s{\Ad724_}{careoncloud_};

        # Refuse rather than collide: a leftover target would silently shadow the data.
        if ( !$DBObject->Prepare( SQL => "SHOW TABLES LIKE '$New'" ) ) {
            return $Self->ExitCodeError();
        }
        my $Exists = 0;
        while ( my @R = $DBObject->FetchrowArray() ) { $Exists = 1 }

        if ($Exists) {
            $Self->PrintError("Target table already exists, refusing: $New\n");
            return $Self->ExitCodeError();
        }

        next TABLE if !$Execute;

        if ( !$DBObject->Do( SQL => "RENAME TABLE $Table TO $New" ) ) {
            $Self->PrintError("Could not rename $Table.\n");
            return $Self->ExitCodeError();
        }
    }

    # -----------------------------------------------------------------------
    # 2. SysConfig setting names and their stored payloads,
    #    and 3. the package repository entries
    # -----------------------------------------------------------------------
    my @Text = (
        { Table => 'sysconfig_default',         Key => ['id'], Columns => [ 'name', 'description', 'effective_value' ] },
        { Table => 'sysconfig_default_version', Key => ['id'], Columns => [ 'name', 'description', 'effective_value', 'xml_content_raw', 'xml_content_parsed' ] },
        { Table => 'sysconfig_modified',        Key => ['id'], Columns => [ 'name', 'effective_value' ] },
        { Table => 'package_repository',        Key => ['id'], Columns => [ 'name', 'filename', 'content' ] },
    );

    my $TotalRows = 0;

    ENTRY:
    for my $Entry (@Text) {
        my $Table   = $Entry->{Table};
        my @Key     = @{ $Entry->{Key} };
        my @Columns = @{ $Entry->{Columns} };

        my $SQL = 'SELECT ' . join( ', ', @Key, @Columns ) . " FROM $Table";
        return $Self->ExitCodeError() if !$DBObject->Prepare( SQL => $SQL );

        my @Rows;
        while ( my @Data = $DBObject->FetchrowArray() ) {
            push @Rows, \@Data;
        }

        my $Changed = 0;

        ROW:
        for my $Row (@Rows) {
            my @KeyValues = @{$Row}[ 0 .. $#Key ];
            my @Values    = @{$Row}[ scalar(@Key) .. $#{$Row} ];

            my @New;
            my $Dirty = 0;

            for my $Value (@Values) {
                if ( !defined $Value || index( $Value, "\0" ) >= 0 ) {
                    push @New, $Value;
                    next;
                }

                my $Updated = $Value;
                $Updated =~ s{D724}{CareOnCloud}g;
                $Updated =~ s{d724}{careoncloud}g;

                $Dirty = 1 if $Updated ne $Value;
                push @New, $Updated;
            }

            next ROW if !$Dirty;
            $Changed++;

            next ROW if !$Execute;

            my $UpdateSQL = "UPDATE $Table SET "
                . join( ', ', map {"$_ = ?"} @Columns )
                . ' WHERE ' . join( ' AND ', map {"$_ = ?"} @Key );

            my @Bind = ( ( map { \$_ } @New ), ( map { \$_ } @KeyValues ) );

            if ( !$DBObject->Do( SQL => $UpdateSQL, Bind => \@Bind ) ) {
                $Self->PrintError("Could not update $Table.\n");
                return $Self->ExitCodeError();
            }
        }

        $TotalRows += $Changed;
        $Self->Print("  $Table: $Changed row(s)\n");
    }

    $Self->Print("\n" . scalar(@Tables) . " table(s) and $TotalRows row(s)");
    $Self->Print( $Execute ? " <green>migrated</green>.\n" : " <yellow>would be migrated</yellow>.\n" );

    if ( $Execute ) {
        $Kernel::OM->Get('Kernel::System::Cache')->CleanUp();
        $Self->Print("\nCache cleared.\n");
        $Self->Print("<yellow>Now run: bin/careoncloud.Console.pl Maint::Config::Rebuild</yellow>\n");
    }

    return $Self->ExitCodeOk();
}

1;
