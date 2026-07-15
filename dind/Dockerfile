# =====================================================================
# Docker-in-Docker daemon image for CI services (GitHub Actions jobs,
# GitLab CI `services:`, or a local isolated daemon), Debian 13.
# Provides dockerd + containerd + runc + docker CLI from the Debian
# archive; versions are frozen by the pinned Debian release, so a given
# DEBIAN_VERSION always yields the same engine version.
# =====================================================================
ARG DEBIAN_VERSION=13
FROM debian:${DEBIAN_VERSION}-slim

ENV DEBIAN_FRONTEND=noninteractive

# `apt-get upgrade` first pulls security fixes for base-image packages
# that `install` alone would not refresh.
#   - openssl              -> self-signed cert set for the TLS mode (2376)
#   - docker-cli           -> Trixie splits the client out of docker.io; the
#                             CLI enables in-container healthchecks/debugging
#   - uidmap               -> rootless/userns support
#   - e2fsprogs, xfsprogs  -> mkfs for dockerd storage drivers
RUN apt-get update && \
    apt-get upgrade -y && \
    apt-get install -y --no-install-recommends \
    ca-certificates \
    openssl \
    docker.io \
    docker-cli \
    containerd \
    runc \
    iptables \
    uidmap \
    e2fsprogs \
    xfsprogs && \
    rm -rf /var/lib/apt/lists/*

# --- OCI labels (aligned with the toolbox image) ---
ARG DEBIAN_VERSION
ARG DOCKER_VERSION=""
ARG REPO_URL="https://github.com/furati/IaC-Multi-Toolbox.git"
LABEL org.opencontainers.image.title="dind" \
    org.opencontainers.image.description="Docker-in-Docker daemon for CI services (Debian 13)" \
    org.opencontainers.image.url=${REPO_URL} \
    org.opencontainers.image.source=${REPO_URL} \
    org.opencontainers.image.version=${DOCKER_VERSION} \
    org.opencontainers.image.licenses="MIT" \
    tool.docker.version=${DOCKER_VERSION} \
    os.debian.version=${DEBIAN_VERSION} \
    org.opencontainers.image.vendor="Ralf Buhlrich <ralf@buhlrich.com>"

# Non-TLS by default; set DOCKER_TLS_CERTDIR (e.g. /certs) to enable TLS mode.
ENV DOCKER_TLS_CERTDIR=""

COPY dockerd-entrypoint.sh /usr/local/bin/dockerd-entrypoint.sh
RUN chmod +x /usr/local/bin/dockerd-entrypoint.sh

# 2375 = plain tcp (non-TLS), 2376 = tcp+TLS.
EXPOSE 2375 2376
VOLUME /var/lib/docker

ENTRYPOINT ["/usr/local/bin/dockerd-entrypoint.sh"]
