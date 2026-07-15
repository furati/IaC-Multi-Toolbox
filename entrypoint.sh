#!/bin/bash
# Entrypoint for the IaC toolbox image.
#
# 1. Maps HOST_UID/HOST_GID onto a container user (gosu) so files created on
#    mounted volumes belong to the host user.
# 2. Falls back to the non-root default user 'dev' when no HOST_UID/GID is set.
# 3. If a Docker socket is mounted, adds the target user to its owning group so
#    the docker CLI works without root (docker-out-of-docker). Not needed with
#    DOCKER_HOST=tcp:// pointing at a dind service.
# 4. Optionally installs project roles/collections from a requirements.yml.
#
# Escape hatches: RUN_AS_ROOT=1 skips the privilege drop; a container already
# started as non-root (e.g. a devcontainer's remoteUser) is passed through.
set -euo pipefail

# Already non-root: nothing to map, nothing to drop.
if [ "$(id -u)" -ne 0 ]; then
    exec "$@"
fi

if [ "${RUN_AS_ROOT:-0}" = "1" ]; then
    exec "$@"
fi

USER_NAME="dev"

# --- 1. HOST_UID/HOST_GID mapping -------------------------------------------
if [ -n "${HOST_UID:-}" ] && [ -n "${HOST_GID:-}" ]; then
    # Group (with -K to allow very high GIDs from AD/LDAP)
    if ! getent group "$HOST_GID" >/dev/null; then
        groupadd -K GID_MIN=0 -K GID_MAX=1000000000 --gid "$HOST_GID" hostgroup
        GROUP_NAME="hostgroup"
    else
        GROUP_NAME=$(getent group "$HOST_GID" | cut -d: -f1)
    fi

    # User
    if ! getent passwd "$HOST_UID" >/dev/null; then
        useradd -K UID_MIN=0 -K UID_MAX=1000000000 --uid "$HOST_UID" --gid "$HOST_GID" \
            --create-home --shell /bin/bash hostuser
        USER_NAME="hostuser"
    else
        USER_NAME=$(getent passwd "$HOST_UID" | cut -d: -f1)
        usermod -aG "$GROUP_NAME" "$USER_NAME" 2>/dev/null || true
    fi

    echo "==> Starting as user: $USER_NAME ($HOST_UID) in group: $GROUP_NAME ($HOST_GID)"
fi

# --- 2. Docker socket access (docker-out-of-docker) --------------------------
# When /var/run/docker.sock is bind-mounted, add the target user to the
# socket's owning group so `docker` works without root and without chmod 666.
if [ -S /var/run/docker.sock ]; then
    sock_gid=$(stat -c %g /var/run/docker.sock)
    grp=$(getent group "$sock_gid" | cut -d: -f1 || true)
    if [ -z "$grp" ]; then
        groupadd -g "$sock_gid" dockersock 2>/dev/null || true
        grp=$(getent group "$sock_gid" | cut -d: -f1 || echo dockersock)
    fi
    usermod -aG "$grp" "$USER_NAME" 2>/dev/null || true
fi

# --- 3. Optional runtime Ansible dependencies --------------------------------
# Runs as the target user so roles/collections land in *their* ~/.ansible.
for req in "${PWD}/requirements.yml" /workbench/requirements.yml; do
    if [ -f "$req" ]; then
        echo "==> Installing Ansible dependencies from $req"
        gosu "$USER_NAME" ansible-galaxy install -r "$req" || true
        break
    fi
done

# --- 4. Drop to the target user (mapped hostuser or the non-root 'dev') ------
exec gosu "$USER_NAME" "$@"
