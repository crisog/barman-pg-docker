#!/bin/bash
set -e

BARMAN_CONF="/etc/barman.conf"
TEMP_CONF="/tmp/barman.conf"

function customize {
    # ─── Root SSH keys ────────────────────────────────────────────────
    mkdir -p /root/.ssh
    if [ ! -z "$SSH_PRIVATE_KEY" ]; then
        echo "$SSH_PRIVATE_KEY" > /root/.ssh/id_rsa
        echo "$SSH_PUBLIC_KEY"  > /root/.ssh/id_rsa.pub
        echo "$SSH_PUBLIC_KEY"  > /root/.ssh/authorized_keys
    else
        ssh-keygen -t rsa -N "" -f /root/.ssh/id_rsa
        cp /root/.ssh/id_rsa.pub /root/.ssh/authorized_keys
    fi
    chmod 700 /root/.ssh
    chmod 644 /root/.ssh/id_rsa.pub
    chmod 600 /root/.ssh/id_rsa /root/.ssh/authorized_keys

    # ─── Barman user SSH keys ───────────────────────────────────────
    mkdir -p /var/lib/barman/.ssh
    if [ ! -z "$SSH_PRIVATE_KEY" ]; then
        echo "$SSH_PRIVATE_KEY" > /var/lib/barman/.ssh/id_rsa
        echo "$SSH_PUBLIC_KEY"  > /var/lib/barman/.ssh/id_rsa.pub
        echo "$SSH_PUBLIC_KEY"  > /var/lib/barman/.ssh/authorized_keys
    else
        cp /root/.ssh/id_rsa /var/lib/barman/.ssh/id_rsa
        cp /root/.ssh/id_rsa.pub /var/lib/barman/.ssh/id_rsa.pub
        cp /root/.ssh/authorized_keys /var/lib/barman/.ssh/authorized_keys
    fi
    chmod 700 /var/lib/barman/.ssh
    chmod 644 /var/lib/barman/.ssh/id_rsa.pub
    chmod 600 /var/lib/barman/.ssh/id_rsa /var/lib/barman/.ssh/authorized_keys
    chown -R barman:barman /var/lib/barman/.ssh

    # ─── Barman directories ─────────────────────────────────────────
    mkdir -p /var/log/barman
    chown -R barman:barman /var/log/barman

    mkdir -p /backup/barman
    chown -R barman:barman /backup/barman

    # Create per-server incoming folder for WAL archives
    mkdir -p /backup/barman/postgres-source-db/incoming
    chown -R barman:barman /backup/barman/postgres-source-db

    mkdir -p /etc/barman.d
    chown -R barman:barman /etc/barman.d

    # ─── Barman PostgreSQL credentials ────────────────────────────────────
    if [ ! -z "$POSTGRES_PASSWORD" ]; then
        # Create .pgpass file with credentials
        echo "pg-docker.railway.internal:*:*:barman:${POSTGRES_PASSWORD}" > /var/lib/barman/.pgpass
        chmod 0600 /var/lib/barman/.pgpass
        chown barman:barman /var/lib/barman/.pgpass
    fi

    # Check PostgreSQL connectivity
    if [ "$1" = "barman" ]; then
        echo "Testing PostgreSQL connectivity..."
        su - barman -c "barman check postgres-source-db" || echo "Warning: PostgreSQL connection check failed. This might be normal if the server is still starting up."
    fi

    # Start cron
    /etc/init.d/cron start

    # Start SSH daemon
    /usr/sbin/sshd
    echo "SSH daemon started"
}

# Run setup
customize

# Launch
echo "Starting main command: $@"
if [ "$1" = "barman" ] && [ "$#" -eq 1 ]; then
    echo "Running barman in persistent mode"
    while true; do
        barman list-servers
        sleep 60
    done
else
    exec "$@"
fi
