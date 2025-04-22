#!/bin/bash
set -e

[ -z "$PGDATA" ] && exit 1

cp /var/lib/postgresql/config/pg_hba.conf "$PGDATA/pg_hba.conf"
chown postgres:postgres "$PGDATA/pg_hba.conf"

cat <<EOF >> "$PGDATA/postgresql.conf"
listen_addresses = '*'
wal_level = replica
archive_mode = off
max_wal_senders = 2
max_replication_slots = 2
hba_file = '$PGDATA/pg_hba.conf'
EOF

chown postgres:postgres "$PGDATA/postgresql.conf"
