# 01-init-custom-config.sh
#!/bin/bash
set -e

echo "[$(date)] Starting 01-init-custom-config.sh"

# Copy your custom HBA into the new PGDATA
echo "[$(date)] Copying custom pg_hba.conf to $PGDATA"
cp /var/lib/postgresql/config/pg_hba.conf "$PGDATA/pg_hba.conf"
chown postgres:postgres "$PGDATA/pg_hba.conf"
echo "[$(date)] Successfully updated pg_hba.conf"

# Append core settings to the freshly initialized postgresql.conf
echo "[$(date)] Updating postgresql.conf with custom settings"
cat <<EOF >> "$PGDATA/postgresql.conf"
listen_addresses = '*'
wal_level = hot_standby
archive_mode = on
archive_command = 'rsync -a %p barman@barman-pg-docker-6ed36822.railway.internal:/backup/barman/postgres-source-db/incoming/%f || exit 0'
max_wal_senders = 2
max_replication_slots = 2
hba_file = '$PGDATA/pg_hba.conf'
EOF

chown postgres:postgres "$PGDATA/postgresql.conf"
echo "[$(date)] Successfully updated postgresql.conf"

echo "[$(date)] Completed 01-init-custom-config.sh"
