#!/bin/bash
set -e

function customize {
    # Ensure the main Barman directory exists and has correct permissions
    # This is important if /var/lib/barman is mounted as a volume
    mkdir -p /var/lib/barman 
    chown -R barman:barman /var/lib/barman

    if [ -z "$SSH_PRIVATE_KEY" ] || [ -z "$SSH_PUBLIC_KEY" ]; then
        echo "ERROR: SSH_PRIVATE_KEY and SSH_PUBLIC_KEY environment variables are required but not set"
        exit 1
    fi

    mkdir -p /root/.ssh
    printf "%s" "$SSH_PRIVATE_KEY" > /root/.ssh/id_ed25519
    printf "%s" "$SSH_PUBLIC_KEY"  > /root/.ssh/id_ed25519.pub
    printf "%s" "$SSH_PUBLIC_KEY"  > /root/.ssh/authorized_keys
    chmod 700 /root/.ssh
    chmod 600 /root/.ssh/id_ed25519* /root/.ssh/authorized_keys

    mkdir -p /var/lib/barman/.ssh
    printf "%s" "$SSH_PRIVATE_KEY" > /var/lib/barman/.ssh/id_ed25519
    printf "%s" "$SSH_PUBLIC_KEY"  > /var/lib/barman/.ssh/id_ed25519.pub
    printf "%s" "$SSH_PUBLIC_KEY"  > /var/lib/barman/.ssh/authorized_keys
    chmod 700 /var/lib/barman/.ssh
    chmod 600 /var/lib/barman/.ssh/id_ed25519* /var/lib/barman/.ssh/authorized_keys
    touch /var/lib/barman/.ssh/authorized_keys
    chmod 600 /var/lib/barman/.ssh/authorized_keys
    
    # Create comprehensive SSH config for barman user only
    cat > /var/lib/barman/.ssh/config <<EOF
# All Railway internal hosts
Host *.railway.internal
  StrictHostKeyChecking no
  UserKnownHostsFile=/dev/null
  IdentityFile /var/lib/barman/.ssh/id_ed25519

# Primary PostgreSQL hosts
Host primary-pg.railway.internal primary-pg*
  StrictHostKeyChecking no
  UserKnownHostsFile=/dev/null

# Standby and recovery PostgreSQL hosts  
Host standby-pg.railway.internal recovery-pg.railway.internal postgrespg.railway.internal standby* recovery*
  StrictHostKeyChecking no
  UserKnownHostsFile=/dev/null
EOF
    chmod 600 /var/lib/barman/.ssh/config
    
    # Ensure barman user owns all SSH files
    chown -R barman:barman /var/lib/barman/.ssh
    
    mkdir -p /var/log/barman
    chown -R barman:barman /var/log/barman

    mkdir -p /etc/barman.d

    if [ -z "$BARMAN_PASSWORD" ]; then
        echo "ERROR: BARMAN_PASSWORD environment variable is required but not set"
        exit 1
    fi
    
    # Use separate BARMAN_PASSWORD for barman user authentication
    cat > /etc/barman.d/pg-primary-db.conf <<EOF
[pg-primary-db]
description = "Primary PostgreSQL on Railway"
conninfo = host=${POSTGRES_HOST} user=barman dbname=${POSTGRES_DB} password=${BARMAN_PASSWORD}
streaming_conninfo = host=${POSTGRES_HOST} user=barman dbname=${POSTGRES_DB} password=${BARMAN_PASSWORD} replication=true
streaming_archiver = on
archiver = off
backup_method = postgres
slot_name = barman_slot

# Retention policies
retention_policy_mode = auto
retention_policy     = RECOVERY WINDOW OF 7 days
wal_retention_policy = main

# Cloud hooks - sync WALs and backups to S3-compatible cloud storage (AWS S3, Cloudflare R2, MinIO, etc.)
# Ensure ENDPOINT_URL and BUCKET_NAME are set
pre_archive_retry_script = /usr/bin/barman-cloud-wal-archive -v --gzip --cloud-provider aws-s3 --endpoint-url ${ENDPOINT_URL} --aws-profile barman-cloud s3://${BUCKET_NAME}/wal-archives pg-primary-db >> /var/log/barman/wal-cloud-upload.log 2>&1 || true
post_backup_retry_script = /usr/bin/barman-cloud-backup -v --gzip --cloud-provider aws-s3 --endpoint-url ${ENDPOINT_URL} --aws-profile barman-cloud s3://${BUCKET_NAME}/base-backups pg-primary-db >> /var/log/barman/backup-cloud-upload.log 2>&1
EOF
    
    chown barman:barman /etc/barman.d/pg-primary-db.conf
    chmod 600 /etc/barman.d/pg-primary-db.conf
    
    echo "${POSTGRES_HOST}:*:*:barman:${BARMAN_PASSWORD}" > /var/lib/barman/.pgpass
    chmod 0600 /var/lib/barman/.pgpass
    chown barman:barman /var/lib/barman/.pgpass
    
    echo "Barman authentication configured"

    if [ -n "$ACCESS_KEY_ID" ] && [ -n "$SECRET_ACCESS_KEY" ]; then
        mkdir -p /var/lib/barman/.aws
        cat > /var/lib/barman/.aws/credentials <<EOF
[barman-cloud]
aws_access_key_id     = ${ACCESS_KEY_ID}
aws_secret_access_key = ${SECRET_ACCESS_KEY}
EOF
        chmod 700 /var/lib/barman/.aws
        chmod 600 /var/lib/barman/.aws/credentials
        chown -R barman:barman /var/lib/barman/.aws
        echo "S3-compatible cloud storage credentials configured"
    else
        echo "Warning: ACCESS_KEY_ID or SECRET_ACCESS_KEY not set; S3-compatible cloud backups will not work"
    fi

    if [ "$1" = "barman" ]; then
        echo "Performing initial Barman checks and setup..."

        sleep 10

        # 1. Start WAL receiver first (required for replication slot check)
        su - barman -c "barman receive-wal pg-primary-db &"
        echo "Barman receive-wal process started in background."

        # Give it a moment to establish connection
        sleep 5
        
        # 2. Run check (for logging/diagnostics, ignore exit status for initial backup decision)
        echo "Running barman check..."
        su - barman -c "barman check pg-primary-db" || echo "Barman check reported issues (see details above)."
        
        # 3. Check for existing backups
        echo "Checking for existing backups..."
        BACKUP_LIST=$(su - barman -c "barman list-backup pg-primary-db" 2>/dev/null || true)
        if ! echo "$BACKUP_LIST" | grep -q '[0-9]\.'; then
            echo "No backups found — preparing for initial backup..."
            
            # Switch WAL and capture the file name Barman expects
            echo "Forcing WAL switch and waiting for archive to complete..."
            WALFILE=$(su - barman -c "barman switch-wal --archive pg-primary-db" 2>/dev/null | awk '/WAL file/ {print $6}')
            
            if [ -n "$WALFILE" ]; then
                echo "Waiting for WAL file $WALFILE to be archived..."
                sleep 30
            else
                echo "Could not capture WAL file name, waiting for streaming to stabilize..."
                sleep 30
            fi
            
            # Now perform the initial backup
            echo "Launching initial base backup (this may take a while)..."
            # Use --wait flag to ensure backup completes before cloud upload
            if su - barman -c "barman backup --wait pg-primary-db"; then
                echo "Initial base backup completed successfully."
            else
                echo "Warning: Initial base backup failed. Check Barman logs."
            fi
        else
            echo "Existing backups found — skipping WAL initialization."
        fi
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