#!/bin/sh
set -e # Beende bei Fehlern sofort

if [ -n "$HOST_UID" ] && [ -n "$HOST_GID" ]; then
    # 1. Gruppe behandeln
    # Prüfe, ob die GID schon vergeben ist
    EXISTING_GROUP=$(getent group "$HOST_GID" | cut -d: -f1)
    if [ -z "$EXISTING_GROUP" ]; then
        addgroup -g "$HOST_GID" iacgroup
        GROUP_NAME="iacgroup"
    else
        GROUP_NAME="$EXISTING_GROUP"
    fi

    # 2. User behandeln
    # Prüfe, ob die UID schon vergeben ist
    EXISTING_USER=$(getent passwd "$HOST_UID" | cut -d: -f1)
    if [ -z "$EXISTING_USER" ]; then
        adduser -D -u "$HOST_UID" -G "$GROUP_NAME" iacuser
        USER_NAME="iacuser"
    else
        USER_NAME="$EXISTING_USER"
        # Stelle sicher, dass der existierende User in der Gruppe ist
        addgroup "$USER_NAME" "$GROUP_NAME" 2>/dev/null || true
    fi

    # Docker-Socket nutzbar machen — über die Besitz-Gruppe statt welt-schreibbar
    # (vermeidet chmod 666). Nur der iacuser erhält Zugriff.
    if [ -S /var/run/docker.sock ]; then
        SOCK_GID=$(stat -c '%g' /var/run/docker.sock 2>/dev/null || echo "")
        if [ -n "$SOCK_GID" ]; then
            SOCK_GROUP=$(getent group "$SOCK_GID" | cut -d: -f1)
            if [ -z "$SOCK_GROUP" ]; then
                addgroup -g "$SOCK_GID" dockersock 2>/dev/null || true
                SOCK_GROUP=$(getent group "$SOCK_GID" | cut -d: -f1)
            fi
            if [ -n "$SOCK_GROUP" ]; then
                addgroup "$USER_NAME" "$SOCK_GROUP" 2>/dev/null || true
            fi
        fi
    fi

    # 3. Home & Berechtigungen
    HOMEDIR=$(getent passwd "$USER_NAME" | cut -d: -f6)
    chown -R "$USER_NAME":"$GROUP_NAME" "$HOMEDIR" 2>/dev/null || true

    cd /workbench

    # 4. Ausführen
    echo "Starte als User: $USER_NAME ($HOST_UID) in Gruppe: $GROUP_NAME ($HOST_GID)"
    exec su-exec "$USER_NAME" "$@"
fi

exec "$@"