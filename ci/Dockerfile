# Only repository configuration is copied from the official Neon image.
FROM invent-registry.kde.org/neon/docker-images/plasma@sha256:f58f9b97f218ee976cf928f6fe00abb929a644aded8c9dfb02f77a9b2a6e1732 AS neon

# Ubuntu 24.04 Linux/amd64, resolved 2026-10-07.
FROM ubuntu:24.04@sha256:f610ab94648195aa356059f5b41d6085c9d4d903c072430cdd1af7bdb646106b
LABEL org.opencontainers.image.source="https://github.com/Lucenx9/codexbar-plasma"
ENV DEBIAN_FRONTEND=noninteractive LANG=C.UTF-8
COPY --from=neon /etc/apt/keyrings/neon-archive-keyring.asc /etc/apt/keyrings/neon-archive-keyring.asc
COPY --from=neon /etc/apt/sources.list.d/neon.sources /etc/apt/sources.list.d/neon.sources
COPY --from=neon /etc/apt/preferences.d/99-neon-base-files /etc/apt/preferences.d/99-neon-base-files
# Bootstrap HTTPS before ca-certificates is installed in the minimal base.
COPY --from=neon /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt
COPY ci/Dockerfile /tmp/ci-build/ci/Dockerfile
COPY scripts/install-ci-dependencies.sh scripts/install-actionlint.sh /tmp/ci-build/scripts/
# Install and clean in the same layer; consumers do not need APT indexes.
RUN sed -i 's|http://|https://|g' /etc/apt/sources.list.d/ubuntu.sources /etc/apt/sources.list.d/neon.sources \
    && bash /tmp/ci-build/scripts/install-ci-dependencies.sh \
    && cd /tmp/ci-build \
    && sha256sum ci/Dockerfile scripts/install-ci-dependencies.sh scripts/install-actionlint.sh > /usr/local/share/ci-inputs.sha256 \
    && dpkg-query -W > /usr/local/share/ci-packages.txt \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/ci-build
