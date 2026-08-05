#!/usr/bin/env perl
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

use v5.24;
use strict;
use warnings;
use utf8;
use experimental 'bitwise';    # can be removed when "use v5.28" is active
use feature 'bitwise';         # can be removed when "use v5.28" is active

# use lib not needed, as only core modules are used

# core modules
use File::Basename qw(dirname);
use FindBin        qw($RealBin);
use File::Find     qw(find);
use File::stat     qw(stat);
use Getopt::Long   qw(GetOptions);

# CPAN modules

# CareOnCloud ESM modules

# some file scoped for convenience
my ($DryRun);

# for determining the group
my %DefaultGroupNames = (
    Apache => [qw(wwwrun apache www-data www _www)],
    PSGI   => [qw(careoncloud)],
);

# Files/directories that should be ignored and not recursed into.
my @IgnoreFiles = (
    qr{^/\.git$},    # ignore .git, but handle .github and .gitignore
    qr{^/\.tidyall}smx,
    qr{^/\.settings}smx,
    qr{^/\.ssh}smx,
    qr{^/\.gpg}smx,
    qr{^/\.gnupg}smx,
);

# Files to be marked as executable.
my @ExecutableFiles = (
    qr{\.(?:pl|psgi|sh)$}smx,
    qr{^/var/git/hooks/(?:pre|post)-receive$}smx,
    qr{^/hooks/build}smx,
);

# Special files that must not be written by web server user.
my @ProtectedFiles = (
    qr{^/\.fetchmailrc$}smx,
    qr{^/\.procmailrc$}smx,
);

my $ExitStatus = 0;

sub PrintUsageAndExit {
    my ( $DefaultGroupNames, $ExitCode ) = @_;

    print <<"END_USAGE";

Set CareOnCloud ESM file permissions.

Usage:
 careoncloud.SetPermissions.pl [--careoncloud-user=<CAREONCLOUD_USER>] [--web-group=<GROUP>] [--admin-group=<ADMIN_GROUP>] [--skip-article-dir] [--skip-regex="REGEX"] [--dry-run]

Options:
 [--careoncloud-user=<CAREONCLOUD_USER>]   - CareOnCloud ESM user, defaults to 'careoncloud'.
 [--web-group=<GROUP>]         - Web server group, per default the first found group is used.
                                 PSGI:   @{[ join ', ', $DefaultGroupNames->{PSGI}->@* ]}
                                 Apache: @{[ join ', ', $DefaultGroupNames->{Apache}->@* ]}
 [--admin-group=<ADMIN_GROUP>] - Admin group, defaults to 'root'.
 [--skip-article-dir]          - Skip var/article as it might take too long on some systems.
 [--skip-regex="REGEX"]        - Add another skip regex like "^/var/my/directory". Paths start with / but are relative to the CareOnCloud ESM directory. --skip-regex can be specified multiple times.
 [--dry-run]                   - Only report, don't change.
 [--help]                      - Display help for this command.

Calling this script without any options it will try to detect the correct user and group settings needed for your setup.

    careoncloud.SetPermissions.pl

END_USAGE

    exit $ExitCode;
}

sub Run {

    if ( $> != 0 ) {    # $EFFECTIVE_USER_ID
        print STDERR "ERROR: Please run this script as superuser (root).\n";

        exit 1;
    }

    # default values for command line options
    my $AdminGroup = 'root';    # default: root
    my $CareOnCloudUser =
        my $Group = '';
    my $Help           = 0;
    my $SkipArticleDir = 0;
    my @SkipRegex;
    my $RunsUnderDocker = $ENV{CAREONCLOUD_RUNS_UNDER_DOCKER} ? 1 : 0;

    # parse the command line parameters
    # for $CareOnCloudUser and $Group the passed args have highest precedence
    GetOptions(
        'help'              => \$Help,
        'careoncloud-user=s'      => \$CareOnCloudUser,
        'web-group=s'       => \$Group,
        'admin-group=s'     => \$AdminGroup,
        'dry-run'           => \$DryRun,
        'skip-article-dir'  => \$SkipArticleDir,
        'skip-regex=s'      => \@SkipRegex,
        'runs-under-docker' => \$RunsUnderDocker,
    ) || PrintUsageAndExit( \%DefaultGroupNames, 1 );

    if ($Help) {
        PrintUsageAndExit( \%DefaultGroupNames, 0 );
    }

    # env vars has precedence under Docker
    if ($RunsUnderDocker) {
        $Group     ||= $ENV{CAREONCLOUD_GROUP};
        $CareOnCloudUser ||= $ENV{CAREONCLOUD_USER};
    }

    # for the default group we might have to try some candidates
    if ( !$Group ) {
        my @GroupCandidates = $RunsUnderDocker
            ?
            $DefaultGroupNames{PSGI}->@*
            :
            $DefaultGroupNames{Apache}->@*;

        CANDIDATE:
        for my $Candidate (@GroupCandidates) {
            my ($GroupName) = getgrnam $Candidate;
            if ($GroupName) {
                $Group = $GroupName;

                last CANDIDATE;
            }
        }
    }

    # now really the default user
    $CareOnCloudUser ||= 'careoncloud';

    # check params
    my $CareOnCloudUserID = getpwnam $CareOnCloudUser;
    if ( !$CareOnCloudUser || !defined $CareOnCloudUserID ) {
        say STDERR "ERROR: --careoncloud-user is missing or invalid.";

        exit 1;
    }

    my $GroupID = getgrnam $Group;
    if ( !$Group || !defined $GroupID ) {
        say STDERR "ERROR: --web-group is missing or invalid.";
        exit 1;
    }

    my $AdminGroupID = getgrnam $AdminGroup;
    if ( !$AdminGroup || !defined $AdminGroupID ) {
        say STDERR "ERROR: --admin-group is invalid.";

        exit 1;
    }

    if ($SkipArticleDir) {
        push @IgnoreFiles, qr{^/var/article}smx;
    }

    for my $Regex (@SkipRegex) {
        push @IgnoreFiles, qr{$Regex}smx;
    }

    my $CareOnCloudDirectory = dirname($RealBin);
    say "Setting permissions on $CareOnCloudDirectory";
    find(
        {
            wanted => sub {
                SetPermissions( $CareOnCloudDirectory, $CareOnCloudUserID, $GroupID, $AdminGroupID );
            },
            no_chdir => 1,
            follow   => 1,
        },
        $CareOnCloudDirectory,
    );

    exit $ExitStatus;
}

sub SetPermissions {
    my ( $CareOnCloudDirectory, $CareOnCloudUserID, $GroupID, $AdminGroupID ) = @_;

    # First get a canonical full filename
    my $File = $File::Find::fullname;

    # If the link is a dangling symbolic link, then fullname will be set to undef.
    return unless defined $File;

    # Make sure it is inside the CareOnCloud ESM directory to avoid following symlinks outside
    my $CareOnCloudDirectoryLength = length $CareOnCloudDirectory;
    if ( substr( $File, 0, $CareOnCloudDirectoryLength ) ne $CareOnCloudDirectory ) {
        $File::Find::prune = 1;    # don't descend into subdirectories

        return;
    }

    # Now get a canonical relative filename under the CareOnCloud ESM directory
    my $RelativeFile = substr( $File, $CareOnCloudDirectoryLength ) || '/';

    for my $IgnoreRegex (@IgnoreFiles) {
        if ( $RelativeFile =~ $IgnoreRegex ) {
            $File::Find::prune = 1;    # don't descend into subdirectories
            say "Skipping $RelativeFile";

            return;
        }
    }

    # Ok, get target permissions for file
    SetFilePermissions( $File, $RelativeFile, $CareOnCloudUserID, $GroupID, $AdminGroupID );

    return;
}

sub SetFilePermissions {
    my ( $File, $RelativeFile, $CareOnCloudUserID, $GroupID, $AdminGroupID ) = @_;

    ## no critic (ProhibitLeadingZeros)
    # Writable by default, owner CareOnCloud ESM and group webserver.
    my ( $TargetPermission, $TargetUserID, $TargetGroupID ) = ( 0660, $CareOnCloudUserID, $GroupID );
    if ( -d $File ) {

        # SETGID for all directories so that both CareOnCloud ESM and the web server can write to the files.
        # Other users should be able to read and cd to the directories.
        $TargetPermission = 02775;
    }
    else {
        # Executable bit for script files.
        EXECUTABLE_REGEX:
        for my $ExecutableRegex (@ExecutableFiles) {
            if ( $RelativeFile =~ $ExecutableRegex ) {
                $TargetPermission = 0770;

                last EXECUTABLE_REGEX;
            }
        }

        # Some files are protected and must not be written by webserver. Set admin group.
        PROTECTED_REGEX:
        for my $ProtectedRegex (@ProtectedFiles) {
            if ( $RelativeFile =~ $ProtectedRegex ) {
                $TargetPermission = -d $File ? 0750 : 0640;
                $TargetGroupID    = $AdminGroupID;

                last PROTECTED_REGEX;
            }
        }
    }

    # Special treatment for toplevel folder: this must be readonly,
    #   otherwise procmail will refuse to read .procmailrc (see bug#9391).
    if ( $RelativeFile eq '/' ) {
        $TargetPermission = 0755;
    }

    # There seem to be cases when stat does not work on a dangling link, skip in this case.
    my $Stat = stat($File) || return;
    if ( ( $Stat->mode() & 07777 ) != $TargetPermission ) {
        if ($DryRun) {
            print sprintf(
                "$RelativeFile permissions %o -> %o\n",
                $Stat->mode() & 07777,
                $TargetPermission
            );
        }
        elsif ( !chmod( $TargetPermission, $File ) ) {
            print STDERR sprintf(
                "ERROR: could not change $RelativeFile permissions %o -> %o: $!\n",
                $Stat->mode() & 07777,
                $TargetPermission
            );
            $ExitStatus = 1;
        }
    }

    if ( ( $Stat->uid() != $TargetUserID ) || ( $Stat->gid() != $TargetGroupID ) ) {
        if ($DryRun) {
            print sprintf(
                "$RelativeFile ownership %s:%s -> %s:%s\n",
                $Stat->uid(),
                $Stat->gid(),
                $TargetUserID,
                $TargetGroupID
            );
        }
        elsif ( !chown( $TargetUserID, $TargetGroupID, $File ) ) {
            print STDERR sprintf(
                "ERROR: could not change $RelativeFile ownership %s:%s -> %s:%s: $!\n",
                $Stat->uid(),
                $Stat->gid(),
                $TargetUserID,
                $TargetGroupID
            );
            $ExitStatus = 1;
        }
    }

    return;
}

# do the work
Run();
