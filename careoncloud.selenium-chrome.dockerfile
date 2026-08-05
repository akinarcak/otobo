# This is the build file for the CareOnCloud ESM selenium-chrome Docker image.

# See bin/docker/build_docker_images.sh for how to build locally.
# See also https://doc.otobo.org/manual/installation/10.1/en/content/installation-docker.html

FROM selenium/standalone-chrome:141.0-chromedriver-141.0-20251101 AS careoncloud-selenium-chrome

# For the VNC-viewer, e.g. Remmina
EXPOSE 5900/tcp

# Make sure that /opt/careoncloud exists and is writable by $CAREONCLOUD_USER.
RUN sudo mkdir --parent /opt/careoncloud/scripts/test
RUN sudo chown -R seluser:seluser /opt/careoncloud

# Build context is scripts/test/sample
COPY --chown=seluser:seluser . /opt/careoncloud/scripts/test/sample

# Add some additional meta info to the image.
# This done at the end of the Dockerfile as changed labels and changed args invalidate the layer cache.
# The labels are compliant with https://github.com/opencontainers/image-spec/blob/master/annotations.md .
LABEL maintainer='CareOnCloud ESM <esm@arcak.net>'
LABEL org.opencontainers.image.authors='CareOnCloud ESM <esm@arcak.net>'
LABEL org.opencontainers.image.description='CareOnCloud ESM is an open-source enterprise service management platform'
LABEL org.opencontainers.image.documentation='https://esm.arcak.net'
LABEL org.opencontainers.image.licenses='GPL-3.0-only'
LABEL org.opencontainers.image.title='CareOnCloud ESM selenium-chrome'
LABEL org.opencontainers.image.url=https://github.com/RotherOSS/otobo
LABEL org.opencontainers.image.vendor='CareOn Secure Cloud Services'
ARG BUILD_DATE=unspecified
LABEL org.opencontainers.image.created=$BUILD_DATE
ARG GIT_COMMIT=unspecified
LABEL org.opencontainers.image.revision=$GIT_COMMIT
ARG GIT_REPO=unspecified
LABEL org.opencontainers.image.source=$GIT_REPO
ARG DOCKER_TAG=unspecified
LABEL org.opencontainers.image.version=$DOCKER_TAG
