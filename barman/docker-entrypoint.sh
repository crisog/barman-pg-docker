#!/bin/bash
set -e

# Function to hash passwords the same way as the DB init script
hash_password() {
    local password="$1"
    local username="$2"
    echo -n "md5${password}${username}" | md5sum | cut -d' ' -f1
}

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
    touch /var/lib/barman/.ssh/authorized_keys
    chmod 600 /var/lib/barman/.ssh/authorized_keys
    
    mkdir -p /var/log/barman
    chown -R barman:barman /var/log/barman

    mkdir -p /backup/barman/pg-primary-db/incoming
    chown -R barman:barman /backup/barman

    mkdir -p /etc/barman.d

    if [ -n "$POSTGRES_PASSWORD" ]; then
        BARMAN_HASHED_PASS=$(hash_password "$POSTGRES_PASSWORD" "barman")
        
        cat > /etc/barman.d/pg-primary-db.conf <<EOF
[pg-primary-db]
description = "Primary PostgreSQL on Railway"
conninfo = host=${POSTGRES_HOST} user=${POSTGRES_USER} dbname=${POSTGRES_DB} password=$BARMAN_HASHED_PASS
streaming_conninfo = host=${POSTGRES_HOST} user=${POSTGRES_USER} dbname=${POSTGRES_DB} password=$BARMAN_HASHED_PASS replication=true
streaming_archiver = on
archiver = off
backup_method = postgres
slot_name = barman_slot

# Retention policies
retention_policy_mode = auto
retention_policy     = RECOVERY WINDOW OF 7 days
wal_retention_policy = main

# Cloud hooks - sync WALs and backups to S3/R2
# Ensure R2_ACCOUNT_ID and R2_BUCKET are set
pre_archive_retry_script = /usr/bin/barman-cloud-wal-archive --cloud-provider aws-s3 --endpoint-url https://${R2_ACCOUNT_ID}.r2.cloudflarestorage.com --aws-profile barman-cloud s3://${R2_BUCKET}/wal-archives pg-primary-db \\\${WAL_FILE}
post_backup_retry_script = /usr/bin/barman-cloud-backup --cloud-provider aws-s3 --endpoint-url https://${R2_ACCOUNT_ID}.r2.cloudflarestorage.com --aws-profile barman-cloud s3://${R2_BUCKET}/base-backups pg-primary-db
EOF
        
        chown barman:barman /etc/barman.d/pg-primary-db.conf
        chmod 600 /etc/barman.d/pg-primary-db.conf
        
        echo "primary-pg.railway.internal:*:*:barman:$BARMAN_HASHED_PASS" > /var/lib/barman/.pgpass
        chmod 0600 /var/lib/barman/.pgpass
        chown barman:barman /var/lib/barman/.pgpass
        
        echo "PostgreSQL password configured with proper MD5 hash"
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

    if [ "$1" = "barman" ]; then
        su - barman -c "barman check pg-primary-db" \
          || echo "Warning: PostgreSQL connection check failed (server may still be starting)"
    fi

    /etc/init.d/cron start
    /usr/sbin/sshd
    echo "SSH daemon started"
}

customize "$@"

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