#!/bin/bash
set -e

BARMAN_CONF="/etc/barman.conf"
TEMP_CONF="/tmp/barman.conf"

function customize {
    mkdir -p /root/.ssh
    if [ -n "$SSH_PRIVATE_KEY" ]; then
        printf "%s" "$SSH_PRIVATE_KEY" > /root/.ssh/id_rsa
        printf "%s" "$SSH_PUBLIC_KEY"  > /root/.ssh/id_rsa.pub
        printf "%s" "$SSH_PUBLIC_KEY"  > /root/.ssh/authorized_keys
    else
        ssh-keygen -t rsa -N "" -f /root/.ssh/id_rsa
        cp /root/.ssh/id_rsa.pub /root/.ssh/authorized_keys
    fi
    chmod 700 /root/.ssh
    chmod 600 /root/.ssh/id_rsa* /root/.ssh/authorized_keys

    mkdir -p /var/lib/barman/.ssh
    if [ -n "$SSH_PRIVATE_KEY" ]; then
        printf "%s" "$SSH_PRIVATE_KEY" > /var/lib/barman/.ssh/id_rsa
        printf "%s" "$SSH_PUBLIC_KEY"  > /var/lib/barman/.ssh/id_rsa.pub
        printf "%s" "$SSH_PUBLIC_KEY"  > /var/lib/barman/.ssh/authorized_keys
    else
        cp /root/.ssh/id_rsa /var/lib/barman/.ssh/id_rsa
        cp /root/.ssh/id_rsa.pub /var/lib/barman/.ssh/id_rsa.pub
        cp /root/.ssh/authorized_keys /var/lib/barman/.ssh/authorized_keys
    fi
    chmod 700 /var/lib/barman/.ssh
    chmod 600 /var/lib/barman/.ssh/id_rsa* /var/lib/barman/.ssh/authorized_keys
    chown -R barman:barman /var/lib/barman/.ssh

    mkdir -p /var/log/barman
    chown -R barman:barman /var/log/barman

    mkdir -p /backup/barman/postgres-source-db/incoming
    chown -R barman:barman /backup/barman

    mkdir -p /etc/barman.d
    chown -R barman:barman /etc/barman.d

    if [ -n "$POSTGRES_PASSWORD" ]; then
        echo "pg-docker.railway.internal:*:*:barman:${POSTGRES_PASSWORD}" > /var/lib/barman/.pgpass
        chmod 0600 /var/lib/barman/.pgpass
        chown barman:barman /var/lib/barman/.pgpass
    fi

    if [ -n "$AWS_ACCESS_KEY_ID" ] && [ -n "$AWS_SECRET_ACCESS_KEY" ]; then
        mkdir -p /var/lib/barman/.aws
        cat > /var/lib/barman/.aws/credentials <<EOF
[barman-cloud]
aws_access_key_id     = ${AWS_ACCESS_KEY_ID}
aws_secret_access_key = ${AWS_SECRET_ACCESS_KEY}
EOF
        chmod 700 /var/lib/barman/.aws
        chmod 600 /var/lib/barman/.aws/credentials
        chown -R barman:barman /var/lib/barman/.aws
        echo "AWS/R2 credentials configured"
    else
        echo "Warning: AWS_ACCESS_KEY_ID or AWS_SECRET_ACCESS_KEY not set; cloud backups will not work"
    fi

    # ─── PostgreSQL connectivity check (optional) ────────────────────
    if [ "$1" = "barman" ]; then
        su - barman -c "barman check postgres-source-db" \
          || echo "Warning: PostgreSQL connection check failed (server may still be starting)"
    fi

    /etc/init.d/cron start
    /usr/sbin/sshd
    echo "SSH daemon started"
}

customize "$@"

if [ -n "$RECOVERY_TIME" ]; then
  echo "Triggering one-off recovery to ${RECOVERY_TIME}"
  barman recover \
    --remote-ssh-command "ssh postgres@${STANDBY_HOST:-standby-host}" \
    --target-time "${RECOVERY_TIME}" \
    postgres-source-db latest \
    "${STANDBY_PGDATA:-/var/lib/postgresql/data/pgdata}" \
  &
fi

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
