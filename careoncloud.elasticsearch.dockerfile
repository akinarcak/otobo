# This is the build file for the OTOBO Elasticsearch docker image.

# The only reason for having a custom Elasticsearch image in OTOBO
# is that additional plugins are installed.

# See also bin/docker/build_docker_images.sh
# See also https://doc.otobo.org/manual/installation/10.1/en/content/installation-docker.html

# Using a version tag that specifies the patch version because no 'latest' tag is provided on Docker Hub.
FROM elasticsearch:9.4.4 AS careoncloud-elasticsearch

# Install important plugins
RUN bin/elasticsearch-plugin install --batch ingest-attachment
RUN bin/elasticsearch-plugin install --batch analysis-icu

# We want an UTF-8 console
ENV LC_ALL=C.UTF-8
ENV LANG=C.UTF-8

# Add some additional meta info to the image.
# This done at the end of the Dockerfile as changed labels and changed args invalidate the layer cache.
# The labels are compliant with https://github.com/opencontainers/image-spec/blob/master/annotations.md .
LABEL maintainer='CareOnCloud ESM <esm@arcak.net>'
LABEL org.opencontainers.image.authors='CareOnCloud ESM <esm@arcak.net>'
LABEL org.opencontainers.image.description='CareOnCloud ESM is an open-source enterprise service management platform'
LABEL org.opencontainers.image.documentation='https://esm.arcak.net'
LABEL org.opencontainers.image.licenses='GPL-3.0-only'
LABEL org.opencontainers.image.title='CareOnCloud ESM elasticsearch'
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
