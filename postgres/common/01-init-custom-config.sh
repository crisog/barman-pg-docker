#!/bin/bash
set -e

# ensure PGDATA is set
[ -z "$PGDATA" ] && exit 1

# copy in your pg_hba and update perms
cp /var/lib/postgresql/config/pg_hba.conf "$PGDATA/pg_hba.conf"
chown postgres:postgres "$PGDATA/pg_hba.conf"

# append core settings
cat <<EOF >> "$PGDATA/postgresql.conf"
listen_addresses = '*'
wal_level = hot_standby
archive_mode = on
archive_command = 'rsync -a %p barman@barman.railway.internal:/backup/barman/postgres-source-db/incoming/%f'
max_wal_senders = 2
max_replication_slots = 2
hba_file = '$PGDATA/pg_hba.conf'
EOF

chown postgres:postgres "$PGDATA/postgresql.conf"
