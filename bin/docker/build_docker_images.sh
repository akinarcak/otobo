#!/usr/bin/env bash

# --
# CareOnCloud ESM is a web-based ticketing system for service organisations.
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

# Just a small helper for building the CareOnCloud ESM Docker images locally.
# For productive use please use the images that are available from Docker Hub.

# Formerly the building was compatible with automated builds on Docker Hub.
# See https://docs.docker.com/docker-hub/builds/advanced/.
# This is no longer the case as automated building is now done with GitHub Actions.

# this function calls "docker build"
build () {
    local DOCKER_FILE=$1;
    local DOCKER_TARGET=$2;
    local DOCKER_TAG=$3;
    local GIT_COMMIT=$4;
    local GIT_BRANCH=$5;
    local BUILD_PATH=$6;
    local IMAGE_NAME=$7;

    # build the Docker image with Buildkit
    # add the option '--progress plain' for seeing the printed output
    docker buildx build\
    --build-arg "BUILD_DATE=$(date -u +'%Y-%m-%dT%H:%M:%SZ')"\
    --build-arg "DOCKER_TAG=$DOCKER_TAG"\
    --build-arg "GIT_COMMIT=$GIT_COMMIT"\
    --build-arg "GIT_BRANCH=$GIT_BRANCH"\
    --build-arg "GIT_REPO=$(git config --get remote.origin.url)"\
    -f "$DOCKER_FILE"\
    -t "$IMAGE_NAME"\
    --target="$DOCKER_TARGET"\
    $BUILD_PATH
}

# environment vars for all Docker images built by this script
GIT_BRANCH=$(git branch --show-current)   # will be empty in detached HEAD
GIT_COMMIT=$(git rev-parse HEAD)          # also works in detached HEAD
careoncloud_version=$(perl -lne 'print $1 if /VERSION\s*=\s*(\S+)/' < RELEASE)
DOCKER_TAG="local-${careoncloud_version}"

# build careoncloud for the services web and daemon
build "careoncloud.web.dockerfile" "careoncloud-web" $DOCKER_TAG $GIT_COMMIT $GIT_BRANCH "." "careoncloud:$DOCKER_TAG"

# build careoncloud with Kerberos support
build "careoncloud.web.dockerfile" "careoncloud-web-kerberos" $DOCKER_TAG $GIT_COMMIT $GIT_BRANCH "." "careoncloud-kerberos:$DOCKER_TAG"

# Building the web container entails installing Perl distributions from CPAN.
# The exact versions of these distributions are tracked in the file cpanfile.snapshot.
# This file is part of the git repository and is kept up to date for the specific
# release series. It won't be merged into the higher release series.
docker run --rm --entrypoint cat careoncloud-kerberos:$DOCKER_TAG /opt/careoncloud_install/cpanfile.snapshot > cpanfile.docker.snapshot

# build careoncloud-nginx-webproxy
build "careoncloud.nginx.dockerfile" "careoncloud-nginx-webproxy" $DOCKER_TAG $GIT_COMMIT $GIT_BRANCH "scripts/nginx" "careoncloud-nginx-webproxy:$DOCKER_TAG"

# build careoncloud-nginx-kerberos-webproxy
build "careoncloud.nginx.dockerfile" "careoncloud-nginx-kerberos-webproxy" $DOCKER_TAG $GIT_COMMIT $GIT_BRANCH "scripts/nginx" "careoncloud-nginx-kerberos-webproxy:$DOCKER_TAG"

# build careoncloud-elasticsearch
build "careoncloud.elasticsearch.dockerfile" "careoncloud-elasticsearch" $DOCKER_TAG $GIT_COMMIT $GIT_BRANCH "scripts/elasticsearch" "careoncloud-elasticsearch:$DOCKER_TAG"

# build careoncloud-selenium-chrome
build "careoncloud.selenium-chrome.dockerfile" "careoncloud-selenium-chrome" $DOCKER_TAG $GIT_COMMIT $GIT_BRANCH "scripts/test/sample" "careoncloud-selenium-chrome:$DOCKER_TAG"
