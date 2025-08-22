#!/bin/bash
set -e

[ -z "$PGDATA" ] && exit 1

cp /var/lib/postgresql/config/pg_hba.conf "$PGDATA/pg_hba.conf"
chown postgres:postgres "$PGDATA/pg_hba.conf"

cat <<EOF >> "$PGDATA/postgresql.conf"
listen_addresses = '*'
wal_level = replica
wal_compression = on
wal_buffers = 16MB
archive_mode = off
archive_timeout = 60s
max_wal_senders = 10
max_replication_slots = 10
hba_file = '$PGDATA/pg_hba.conf'
checkpoint_completion_target = 0.9
shared_preload_libraries = 'pg_stat_statements'
track_io_timing = on
track_functions = all
EOF

chown postgres:postgres "$PGDATA/postgresql.conf"
