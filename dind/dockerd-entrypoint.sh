#!/bin/sh
# Docker-in-Docker daemon entrypoint for CI services.
#
# - DOCKER_TLS_CERTDIR empty/unset (default): serve plain tcp on 2375 plus the
#   unix socket. Pass --tls=false via the service command if the runner insists.
# - DOCKER_TLS_CERTDIR set (e.g. /certs): generate a CA/server/client cert set
#   once and serve TLS on 2376; the client certs land in
#   $DOCKER_TLS_CERTDIR/client (point DOCKER_CERT_PATH there in the job).
#
# Extra flags from the container command are appended to dockerd.
#
# DNS: some CI runners attach services to a per-build network whose embedded
# resolver (127.0.0.11) dockerd filters out for nested build containers. Pass
# the real DNS server(s) via the DOCKERD_DNS env var (comma-separated); they
# are turned into --dns flags here.
set -eu

: "${DOCKER_HOST_TCP:=tcp://0.0.0.0:2375}"

# Build --dns flags from DOCKERD_DNS (comma-separated). Intentionally unquoted
# on use so multiple flags word-split.
DNS_ARGS=""
if [ -n "${DOCKERD_DNS:-}" ]; then
    OLDIFS=$IFS
    IFS=','
    for _d in $DOCKERD_DNS; do
        [ -n "$_d" ] && DNS_ARGS="$DNS_ARGS --dns=$_d"
    done
    IFS=$OLDIFS
fi

if [ -n "${DOCKER_TLS_CERTDIR:-}" ]; then
    ca="$DOCKER_TLS_CERTDIR/ca"
    srv="$DOCKER_TLS_CERTDIR/server"
    cli="$DOCKER_TLS_CERTDIR/client"
    if [ ! -f "$ca/cert.pem" ]; then
        mkdir -p "$ca" "$srv" "$cli"
        openssl genrsa -out "$ca/key.pem" 4096
        openssl req -x509 -new -key "$ca/key.pem" -days 3650 -subj "/CN=dind-ca" -out "$ca/cert.pem"
        for who in server client; do
            d="$DOCKER_TLS_CERTDIR/$who"
            openssl genrsa -out "$d/key.pem" 4096
            openssl req -new -key "$d/key.pem" -subj "/CN=docker" -out "$d/csr.pem"
            printf 'subjectAltName = DNS:docker,DNS:localhost,IP:127.0.0.1\n' > "$d/ext.cnf"
            openssl x509 -req -in "$d/csr.pem" -CA "$ca/cert.pem" -CAkey "$ca/key.pem" \
                -CAcreateserial -days 3650 -extfile "$d/ext.cnf" -out "$d/cert.pem"
            cp "$ca/cert.pem" "$d/ca.pem"
            rm -f "$d/csr.pem" "$d/ext.cnf"
        done
    fi
    # shellcheck disable=SC2086 # DNS_ARGS must word-split into multiple flags
    exec dockerd \
        --host=unix:///var/run/docker.sock \
        --host=tcp://0.0.0.0:2376 \
        --tlsverify \
        --tlscacert="$ca/cert.pem" \
        --tlscert="$srv/cert.pem" \
        --tlskey="$srv/key.pem" \
        $DNS_ARGS "$@"
fi

# shellcheck disable=SC2086 # DNS_ARGS must word-split into multiple flags
exec dockerd \
    --host=unix:///var/run/docker.sock \
    --host="$DOCKER_HOST_TCP" \
    $DNS_ARGS "$@"
