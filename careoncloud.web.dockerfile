# syntax=docker/dockerfile:1.9

# This is the build file for the OTOBO web docker image.
# The services OTOBO web and OTOBO daemon use the same image.
# There is also an extra build target careoncloud-web-kerberos that adds support for Kerberos.

# See also bin/docker/build_docker_images.sh
# See also https://doc.otobo.org/manual/installation/10.1/en/content/installation-docker.html

# The Debian version is explicitly set to Trixie, that is Debian 13.
# This avoids a surprising change of the version of Debian when the image
# is rebuilt, especially when the image for a new release of OTOBO is built.
# Note that the minor version of Debian may change between builds.
#
# The slim version is used for reducing the size of the image.
#
# The three supported release series 10.1, 11.0, and 11.1 should use
# the same version of Perl. The version of Perl may be updated in a patch level release.
# The version of Debian should only be changed for a new major or minor version of OTOBO.
#
# The individual build targets may add additional Debian or CPAN packages.
FROM perl:5.44-slim-trixie AS base

# First there is some initial setup that needs to be done by root.
USER root

# Install some required and optional Debian packages.
#
# For ODBC see https://blog.devart.com/installing-and-configuring-odbc-driver-on-linux.html
# For ODBC for SQLite, for testing ODBC, see http://www.ch-werner.de/sqliteodbc/html/index.html
#
# The webserver needs to connect to MariaDB service using DBD::mysql. For that purpose
# 'default-mysql-client' is installed. This allows the building
# of the Perl module DBD::mysql. It also installs the command line program 'mysql'.
#
# Create /opt/careoncloud_install already here, in order to reduce the number of build layers.
# hadolint ignore=DL3008
#
# create the otobo user
#   --user-group            create group 'otobo' and add the user to the created group
#   --home-dir /opt/careoncloud   set $HOME of the user
#   --create-home           create /opt/careoncloud
#   --shell /bin/bash       set the login shell, not used here because otobo is system user
#   --comment 'CareOnCloud ESM user'  complete name of the user
#
# Also create /opt/careoncloud_install, /opt/careoncloud, and /opt/careoncloud_update
ENV CAREONCLOUD_USER=careoncloud
ENV CAREONCLOUD_GROUP=careoncloud
ENV CAREONCLOUD_HOME=/opt/careoncloud
ENV DIR_OPT_CAREONCLOUD_UPDATE=/opt/careoncloud_update
RUN apt-get update\
 && DEBIAN_FRONTEND=noninteractive apt-get -y --no-install-recommends install\
 "build-essential"\
 "linux-libc-dev"\
 "pkg-config"\
 "libpq-dev"\
 "libxml2-dev"\
 "libxslt-dev"\
 "libexpat-dev"\
 "default-libmysqlclient-dev"\
 "gpg"\
 "gpg-agent"\
 "ack"\
 "cron"\
 "default-mysql-client"\
 "graphviz"\
 "git"\
 "ldap-utils"\
 "less"\
 "nano"\
 "unixodbc-common" "libodbcinst2" "libodbccr2" "libodbc2" "odbcinst" "unixodbc-dev" "unixodbc"\
 "freetds-bin" "freetds-common" "tdsodbc"\
 "postgresql-client"\
 "redis-tools"\
 "sqlite3" "libsqliteodbc"\
 "rsync"\
 "screen"\
 "telnet"\
 "tree"\
 "vim"\
 "chromium"\
 "chromium-sandbox"\
 "fonts-indic"\
 "fonts-noto"\
 "fonts-noto-cjk"\
 "fonts-noto-color-emoji"\
 "libqrencode-dev"\
 "libreadline-dev"\
 && useradd --user-group --home-dir $CAREONCLOUD_HOME --create-home --shell /bin/bash --comment 'CareOnCloud ESM user' $CAREONCLOUD_USER\
 && install -d /opt/careoncloud_install\
 && install --group $CAREONCLOUD_GROUP --owner $CAREONCLOUD_USER -d $CAREONCLOUD_HOME\
 && install --group $CAREONCLOUD_GROUP --owner $CAREONCLOUD_USER -d $DIR_OPT_CAREONCLOUD_UPDATE

# We want an UTF-8 console
ENV LC_ALL=C.UTF-8
ENV LANG=C.UTF-8

# Install CPAN distributions that are required by OTOBO into the local lib directory /opt/careoncloud_install/local.
# './local' happens to be the default installation directory of carton.
# Installation can be triggered by modifying the file cpanfile.docker.snapshot in any way.
#
# Note that the modules in /opt/careoncloud/Kernel/cpan-lib are not considered by carton.
# This hopefully reduces potential conflicts.
#
# The modules are installed with the command `carton` as it allows to install fixed
# version from a previous snapshot. The idea is that the snapshot is updated when
# running local builds. The automated builds on Github use the saved snapshot.
#
# 'carton install' installs the newest possible version of the CPAN modules when the cpanfile.snapshot does not exist.
# The file cpanfile.snapshot is created, documenting which versions were installed.
# 'carton install --deployment' will install the exact versions from cpanfile.snapshot.
# and it will complain if modules that are not in the snapshot should be installed.
#
# A fatpacked script `carton` is used for building the image. This has the advantage
# that the requirements for `carton` are not included in the generated Docker image.
# `carton` uses internally `cpanm`. `cpanm` is supplied by the Perl base image.
#
# Creating the fatpacked carton script is a bit tedious. See
# https://github.com/perl-carton/carton/issues/237 and https://github.com/miyagawa/cpanminus/pull/577.
# The recommendation is to create the fatpack in an running container:
#   cd /opt/careoncloud
#   cpanm --local-lib local Carton
#   cpanm --local-lib local App::FatPacker
#   sed -e '/version::vpp/s/^/# version:vpp is not in core Perl 5.40:/' -i.bak local/lib/perl5/Menlo/CLI/Compat.pm
#   touch cpanfile
#   carton fatpack
#   rm cpanfile
# On the Docker host the fatpacked /opt/careoncloud_install/vendor/bin/carton can be copied to bin/docker/carton
# in the Git sandbox.
#   docker cp otoelfeins-web-1:/opt/careoncloud/vendor/bin/carton bin/docker/carton
# Look for 'Hotpatch by the OTOBO Team' in the git diff and apply the hot patches to the new version.
#   git add bin/docker/carton
#
# Note that the variable $DOCKER_TAG is already substituted by Docker.
#
# Clean up the .cpanm dir after the installation tasks as that dir is no longer needed
# and the unpacked Perl distributions sometimes have weird user and group IDs.
WORKDIR /opt/careoncloud_install
COPY bin/docker/carton carton
COPY cpanfile.docker cpanfile
COPY cpanfile.docker.snapshot cpanfile.snapshot
ENV PERL5LIB="/opt/careoncloud_install/local/lib/perl5"
ENV PATH="/opt/careoncloud_install/local/bin:${PATH}"
ARG DOCKER_TAG=unspecified
RUN <<END_BASH bash
    set -eux

    if [[ $DOCKER_TAG == local-* ]]
    then
        rm cpanfile.snapshot
        /opt/careoncloud_install/carton install
    else
        /opt/careoncloud_install/carton install --deployment
    fi

    rm -rf "/root/.cpanm"
END_BASH

# Add some additional meta info to the image.
# This done at the end of the Dockerfile as changed labels and changed args invalidate the layer cache.
# The labels are compliant with https://github.com/opencontainers/image-spec/blob/master/annotations.md .
# Titel is specific for the individual targets.
LABEL maintainer='CareOnCloud ESM <esm@arcak.net>'
LABEL org.opencontainers.image.authors='CareOnCloud ESM <esm@arcak.net>'
LABEL org.opencontainers.image.description='CareOnCloud ESM is an open-source enterprise service management platform'
LABEL org.opencontainers.image.documentation='https://esm.arcak.net'
LABEL org.opencontainers.image.licenses='GPL-3.0-only'
LABEL org.opencontainers.image.url='https://github.com/RotherOSS/otobo'
LABEL org.opencontainers.image.vendor='CareOn Secure Cloud Services'

# Tell the web application and bin/careoncloud.SetPermissions.pl that it runs in a container.
# Note that this setting is essential for a correct migration from OTRS 6.
ENV CAREONCLOUD_RUNS_UNDER_DOCKER=1

# the entrypoint is not in the volume
ENTRYPOINT ["/opt/careoncloud_install/entrypoint.sh"]

# The regular build target, without Kerberos
FROM base AS careoncloud-web

# First there is some initial setup that needs to be done by root.
USER root

# No further Debian or CPAN packages are needed,
# so we only need to do the cleanup
RUN rm -rf /var/lib/apt/lists/*

# Copy the OTOBO installation to /opt/careoncloud_install/careoncloud_next and use it as the working dir.
# The files that are set up in .dockerignore. This means that a potentially existing Kernel/Config.pm
# won't be copied. Instead Kernel/Config.pm.docker.dist will be copied to Kernel/Config.pm in entrypoint.sh.
COPY --chown=$CAREONCLOUD_USER:$CAREONCLOUD_GROUP . /opt/careoncloud_install/careoncloud_next
WORKDIR /opt/careoncloud_install/careoncloud_next

# In a running installation additional Perl modules from CPAN might be needed. These be installed
# in the directory /opt/careoncloud/local. This directory is located in the volume /opt/careoncloud and therefore
# survives updates of the Docker image.
# /opt/careoncloud/local must be prepolulated with architecture and version dependent subdirs. These subdirs
# are added to @INC when a Perl process starts up.
RUN perl -Mlocal::lib=local
ENV PERL5LIB="/opt/careoncloud/local/lib/perl5:${PERL5LIB}"
ENV PATH="/opt/careoncloud/local/bin:${PATH}"

# Make sure that /opt/careoncloud exists and is writable by $CAREONCLOUD_USER.
# set up entrypoint.sh and docker_firsttime
# Finally set permissions. Explicitly pass --runs-under-docker as
# $ENV{CAREONCLOUD_RUNS_UNDER_DOCKER} is not yet set.
RUN install --owner $CAREONCLOUD_USER --group $CAREONCLOUD_GROUP -D bin/docker/entrypoint.sh /opt/careoncloud_install/entrypoint.sh\
 && install --owner $CAREONCLOUD_USER --group $CAREONCLOUD_GROUP /dev/null docker_firsttime\
 && perl bin/careoncloud.SetPermissions.pl --runs-under-docker

# perform build steps that can be done as the user otobo.
USER $CAREONCLOUD_USER

# More setup that can be done by the user otobo

# Under Docker the Elasticsearch Daemon is running on the host 'elastic' instead of '127.0.0.1'.
# The webservice configuration is in a YAML file and it is not obvious how
# to change settings for webservices.
# So we take the easy was out and do the change directly in the XML file,
# before installer.pl has run.
# Doing this already in the initial database insert allows installer.pl
# to pick up the changed host and to check whether Elasticsearch is available.
RUN perl -p -i.orig -e "s{Host: http://localhost:9200}{Host: http://elastic:9200}" scripts/database/careoncloud-initial_insert.xml

# Activate SysConfig settings that should override that defaults when running in Docker.
RUN cp Kernel/Config/Files/XML/DockerConfig.xml.dist Kernel/Config/Files/XML/DockerConfig.xml

# Create empty dirs.
# Enable bash completion.
# Add a .vimrc.
# make Docker image identifyable via the files git-(repo|branch|commit).txt
# Create ARCHIVE with hashes of the files in the workdir
ARG GIT_REPO=unspecified
ARG GIT_BRANCH=unspecified
ARG GIT_COMMIT=unspecified
RUN <<END_BASH bash
    set -eux

    install -d var/stats var/packages var/tmp var/httpd/htdocs/static
    (
        echo "# File created by Dockerfile"
        echo ""
        echo "# set up bash completion"
        echo ". ~/.bash_completion"
        echo ""
        echo "# use Page-Up and Page-Down for cycling through autocomplete suggestions"
        echo "bind '\"\\e[6~\": menu-complete'"
        echo "bind '\"\\e[5~\": menu-complete-backward'"
        echo ""
        echo "# helpers"
        echo "alias ..='cd ..'"
        echo "alias ...='cd ../..'"
    ) >> .bash_aliases
    install -m u=rw,g=r,o=r scripts/vim/vimrc .vimrc
    (echo $GIT_REPO   > git-repo.txt)
    (echo $GIT_BRANCH > git-branch.txt)
    (echo $GIT_COMMIT > git-commit.txt)
    bin/careoncloud.CheckSum.pl -a create
END_BASH

# Up to now we have prepared /opt/careoncloud_install/careoncloud_next.
# Merging /opt/careoncloud_install/careoncloud_next and /opt/careoncloud is left to /opt/careoncloud_install/entrypoint.sh.
# Note that for supporting the command 'cron' we need to start as root.
# For all other commands entrypoint.sh switches to the user otobo.
WORKDIR $CAREONCLOUD_HOME

# Titel is specific for the build target
LABEL org.opencontainers.image.title='CareOnCloud ESM'

# These labels change with every build
ARG BUILD_DATE=unspecified
LABEL org.opencontainers.image.created=$BUILD_DATE
LABEL org.opencontainers.image.revision=$GIT_COMMIT
LABEL org.opencontainers.image.source=$GIT_REPO
LABEL org.opencontainers.image.version=$DOCKER_TAG

# This Dockerfile also provides for building images with additional support for Kerberos.
# This image will be built when --target=careoncloud-web-kerberos is specified in the 'docker build' command.
FROM base AS careoncloud-web-kerberos

# First there is some initial setup that needs to be done by root.
USER root

# install Kerberos related Debian packages
RUN apt-get update\
 && DEBIAN_FRONTEND=noninteractive apt-get -y --no-install-recommends install\
 "krb5-user"\
 "libpam-krb5"\
 "libpam-ccreds"\
 "krb5-multidev"\
 "libkrb5-dev"\
 && rm -rf /var/lib/apt/lists/*

# append extra modules needed for Kerberos
# Clean up the .cpanm dir after the installation tasks as that dir is no longer needed
# and the unpacked Perl distributions sometimes have weird user and group IDs.
WORKDIR /opt/careoncloud_install
RUN <<END_BASH bash
    set -eux

    (
        echo "requires 'Authen::Krb5::Simple';"
        echo "requires 'LWP::Authen::Negotiate';"
    ) >> cpanfile

    /opt/careoncloud_install/carton install

    rm -rf "/root/.cpanm"
END_BASH

# perform build steps that can be done as the user otobo.
USER $CAREONCLOUD_USER

# skipping /opt/careoncloud_install/local
COPY --from=careoncloud-web\
 /opt/careoncloud_install/entrypoint.sh\
 /opt/careoncloud_install
COPY --from=careoncloud-web --chown=$CAREONCLOUD_USER:$CAREONCLOUD_GROUP\
 /opt/careoncloud_install/careoncloud_next\
 /opt/careoncloud_install/careoncloud_next

WORKDIR $CAREONCLOUD_HOME

# Titel is specific for the build target
LABEL org.opencontainers.image.title='CareOnCloud ESM Kerberos'

# These labels change with every build
ARG BUILD_DATE=unspecified
LABEL org.opencontainers.image.created=$BUILD_DATE
LABEL org.opencontainers.image.revision=$GIT_COMMIT
LABEL org.opencontainers.image.source=$GIT_REPO
ARG DOCKER_TAG=unspecified
LABEL org.opencontainers.image.version=$DOCKER_TAG
