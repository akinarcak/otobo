#!/usr/bin/env bash

# --
# OTOBO is a web-based ticketing system for service organisations.
# --
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

# Note that in the docker image this file will be available as
# /opt/careoncloud_install/entrypoint.sh .

################################################################################
# Declare file scoped variables
################################################################################

g_dir_careoncloud_next="/opt/careoncloud_install/careoncloud_next"
g_update_log="$CAREONCLOUD_HOME/var/log/update.log"
g_function=true
g_sleep_pid=true

################################################################################
# Declare functions
################################################################################

# does the initial copy to /opt/careoncloud
function handle_docker_firsttime() {

    if [ ! -d  $CAREONCLOUD_HOME ]; then
        # it is required that /opt/careoncloud is mounted
        print_error "the volume $CAREONCLOUD_HOME is not mounted" && exit 1
    elif [ ! "$(ls $CAREONCLOUD_HOME)" ]; then
        # first the simple case: there is no previous installation
        # use a simle 'ls' for checking dir content, hidden files like .bashrc are ignored
        copy_careoncloud_next
    fi

    # When /opt/careoncloud already exists then there is no automatic update.
    # The updating has to be triggered with the explicit commands 'copy_careoncloud_next' and 'do_update_tasks'.

    # we are done, docker_firstime has been handled
    # $g_dir_careoncloud_next is not removed, it is kept for future reference
    # Note that docker_firsttime_handled is only available in the service web.
    mv $g_dir_careoncloud_next/docker_firsttime $g_dir_careoncloud_next/docker_firsttime_handled
}

# Existing application volumes are intentionally not overwritten at web start.
# The canonical API mount is a core runtime file, though, and an older volume
# may predate its introduction. Add it only when absent so an explicit core
# update remains responsible for replacing an existing file.
function ensure_canonical_psgi() {

    local source_psgi="$g_dir_careoncloud_next/bin/psgi-bin/careoncloud.psgi"
    local target_psgi="$CAREONCLOUD_HOME/bin/psgi-bin/careoncloud.psgi"

    if [ -f "$target_psgi" ]; then
        return
    fi

    if [ ! -f "$source_psgi" ]; then
        print_error "canonical PSGI source is missing: $source_psgi"
        exit 1
    fi

    mkdir -p "$(dirname "$target_psgi")"
    cp --archive "$source_psgi" "$target_psgi"
    {
        date
        echo "Restored missing canonical PSGI mount: $target_psgi"
        echo
    } >> "$g_update_log"
}

# An easy way to start bash.
# Or list files.
function exec_whatever() {
    exec $@
}

# Every 2 minutes try to start, or restart, the OTOBO Daemon.
# The Daemon will exit immediately when SecureMode = 0.
# But this is OK, as Cron will restart it and it will run when SecureMode = 1.
# Also gracefully handle the case when /opt/careoncloud is not populated yet.
# The watch command will be run in the forground.
function start_and_check_daemon() {

    # Docker is stopping containers by sending a SIGTERM signal to the PID=1 process.
    # As a fallback it sends SIGKILL after waiting 10s.
    # In the otobo_daemon_1 case the PID=1 process is this script.
    # Catch the SIGTERM signal and stop the child processes.
    # See also https://hynek.me/articles/docker-signals/.
    trap stop_daemon SIGTERM

    g_sleep_pid=
    while true; do

        # Do not try to start the Daemon when /opt/careoncloud is still being created.
        if [ -f ".copy_careoncloud_next_finished" ]; then
            bin/careoncloud.Daemon.pl start
        fi
        # the '&' activates the builtin job control system
        # remember the PID of sleep, so that the process can be terminated in stop_daemon()
        sleep 120 & g_sleep_pid=$!

        # wait until the sleep exits or until a signal arrives,
        # which means that the stop_daemon() can run without having to wait for the sleep command
        wait $g_sleep_pid
        g_sleep_pid=
    done
}

# clean up the OTOBO daemon process
function stop_daemon() {
    if [ -f "bin/careoncloud.Daemon.pl" ]; then
        bin/careoncloud.Daemon.pl stop
        [[ $g_sleep_pid ]] && kill "$g_sleep_pid"
    fi

    # claim that everything is fine
    exit 0
}

# Start the webserver
function exec_web() {

    local otobo_devel="${1:-unknown}"

    # For production use the web server Gazelle, which is implemented in C.
    # In many cases 'deployment' is also the sensible option during development.
    # The special loader Plack::Loader::SyncWithS3 is activated only when S3 is active. That loader module
    # checks for updates in S3.
    if [ "$otobo_devel" = "deployment" ]; then

        s3_active=$(perl -I . -I Kernel/cpan-lib/ -MKernel::Config -E 'my $Conf = Kernel::Config->new(Level => q{Clear}); print $Conf->Get(q{Storage::S3::Active});')
        if [[ "$s3_active" -eq "1" ]]; then
            exec plackup --server Gazelle --env deployment --port 5000 -I $CAREONCLOUD_HOME -I $CAREONCLOUD_HOME/Kernel/cpan-lib --loader SyncWithS3  bin/psgi-bin/careoncloud.psgi
        else
            exec plackup --server Gazelle --env deployment --port 5000 bin/psgi-bin/careoncloud.psgi
        fi

    # For development omit the --env option, thus setting PLACK_ENV to its default value 'development'.
    # This enables additional middlewares that are useful during development.
    elif [ "$otobo_devel" = "development" ]; then
        exec plackup --server Gazelle --port 5000 bin/psgi-bin/careoncloud.psgi

    # For activating profiling. Loading the middleware tells careoncloud.psgi that profiling is enabled.
    elif [ "$otobo_devel" = "nytprof" ]; then
        exec plackup -M Plack::Middleware::Profiler::NYTProf --port 5000 bin/psgi-bin/careoncloud.psgi

    # For being very sure that all modules are reloaded and the config being read again
    elif [ "$otobo_devel" = "shotgun" ]; then
        exec plackup --loader Shotgun --port 5000 bin/psgi-bin/careoncloud.psgi

    # lost
    else
        echo "flag $otobo_devel is not supported"

    fi
}

# Copy /opt/careoncloud_install/careoncloud_next without checking the flag file 'docker_firsttime'.
# Files that had been added in the previous /opt/careoncloud are not discarded.
function copy_careoncloud_next() {

    # Copy files recursively.
    # Changed files are overwritten, new files are not deleted. But note that the target directory
    # is usually empty except var/article.
    # File attributes are preserved.
    # Copying $g_dir_careoncloud_next/. makes it irrelevant whether $CAREONCLOUD_HOME already exists.
    cp --archive $g_dir_careoncloud_next/. $CAREONCLOUD_HOME

    {
        date
        echo "Copied $g_dir_careoncloud_next to $CAREONCLOUD_HOME"
        echo
    } >> $g_update_log

    # clean up
    rm -f $CAREONCLOUD_HOME/docker_firsttime
    rm -f $CAREONCLOUD_HOME/docker_firsttime_handled

    # Make sure that an initial config is available. But don't overwrite existing config.
    # Use the docker specific Config.pm.dist file.
    cp --no-clobber $CAREONCLOUD_HOME/Kernel/Config.pm.docker.dist $CAREONCLOUD_HOME/Kernel/Config.pm

    # Indicate the time when copy_careoncloud_next() was last called. This is used primarily
    # for the OTOBO daemon who needs to know that /opt/careoncloud has been copied completely.
    touch $CAREONCLOUD_HOME/.copy_careoncloud_next_finished
}

function do_update_tasks() {

    # Reinstall packages, rebuild config, purge the cache and the cached loader files.
    # Note that this works only if OTOBO has been properly configured,
    # because some commands need access to the database.
    #
    # Note that Admin::Package::UpgradeAll does a cleanup of the SysConfig when all
    # packages could be upgraded smoothly. In the case of problems there is no cleanup.
    # This strategy allows manual rework using the values from the old SysConfig.
    {
        echo -n  "[$FUNCNAME] started "
        date
        echo "[$FUNCNAME] Admin::Package::ReinstallAll"
        ($CAREONCLOUD_HOME/bin/careoncloud.Console.pl Admin::Package::ReinstallAll --hide-deployment-info 2>&1)
        echo "[$FUNCNAME] Admin::Package::UpgradeAll"
        ($CAREONCLOUD_HOME/bin/careoncloud.Console.pl Admin::Package::UpgradeAll 2>&1)
        echo "[$FUNCNAME] Maint::Config::Rebuild --deploy-acls --deploy-processes"
        ($CAREONCLOUD_HOME/bin/careoncloud.Console.pl Maint::Config::Rebuild --deploy-acls --deploy-processes 2>&1)
        echo "[$FUNCNAME] Maint::Cache::Delete"
        ($CAREONCLOUD_HOME/bin/careoncloud.Console.pl Maint::Cache::Delete 2>&1)
        echo "[$FUNCNAME] Maint::Loader::CacheCleanup"
        ($CAREONCLOUD_HOME/bin/careoncloud.Console.pl Maint::Loader::CacheCleanup 2>&1)
        echo "[$FUNCNAME] Maint::Translations::Deploy"
        ($CAREONCLOUD_HOME/bin/careoncloud.Console.pl Maint::Translations::Deploy --hide-skipped-info 2>&1)
        echo -n "[$FUNCNAME] finished "
        date
        echo
    } >> $g_update_log
}

print_error() {
    echo -e "\e[101m[ERROR]\e[0m $1"
}

################################################################################
# Do the work
################################################################################

# container should not be run as root
if [ ! -z "$UID" ] && [ $UID -eq 0 ]; then
    exit 1
fi

# now running as $CAREONCLOUD_USER

# print usage message when no param was passed
if [ "$1" = "" ]; then
    cat <<END_HELP
This script is meant to be used as a Docker entrypoint script.
Supported arguments are: 'daemon', 'web', 'copy_careoncloud_next', 'copy_otobo_update', and 'do_update_tasks'.
When no argument is passed, then this message is printed.
Any other argument list will be executed as a system command.
END_HELP

    exit 0
fi

# Start the OTOBO daemon
if [ "$1" = "daemon" ]; then

    # When /opt/careoncloud isn't a Docker volume we first check whether the container is started with a new image.
    # If /opt/careoncloud is a volume we assume that there is a web container who does this for us.
    if ! mountpoint -q "/opt/careoncloud"; then

        # There is no locking as we no other container can meddle with /opt/careoncloud.
        if [ -f "$g_dir_careoncloud_next/docker_firsttime" ]; then
            handle_docker_firsttime
        fi
    fi

    # do some work
    start_and_check_daemon

    exit $?
fi

# Start the web server
if [ "$1" = "web" ]; then

    # First check whether the container is started with a new image.
    # There is no locking as we assume that there aren't multiple containers trying to the same.
    if [ -f "$g_dir_careoncloud_next/docker_firsttime" ]; then
        handle_docker_firsttime
    fi

    ensure_canonical_psgi

    # start webserver, passing the optional second parameter
    exec_web "${2:-deployment}"
fi

# Handle the functions that constitute the external interface.
if [[
    $1 = "copy_careoncloud_next"
    ||
    $1 = "do_update_tasks"
]];
then

    # additional parameters are passed to the called function
    g_function="$1"
    shift
    echo "calling $g_function"
    $g_function $@
    echo "finished $g_function"

    exit $?
fi

# as a fallback execute the passed command
exec_whatever $@
