#!/bin/bash
set -e

# This script creates the replication user on the standby server
# to prepare it for eventual promotion to primary

REPLICATION_USER=${REPLICATION_USER:-replicator}
# Create password hash for PostgreSQL md5 authentication
REPLICATION_PASSWORD=$(echo -n "md5${POSTGRES_PASSWORD}${REPLICATION_USER}" | md5sum | cut -d' ' -f1)

echo "Creating replication user for future primary role..."

psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" <<-EOSQL
  -- Create dedicated user for standby replication if it doesn't exist
  DO \$\$
  BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = '$REPLICATION_USER') THEN
      CREATE USER $REPLICATION_USER WITH LOGIN REPLICATION PASSWORD '$REPLICATION_PASSWORD';
      RAISE NOTICE 'Created replication user: $REPLICATION_USER';
    ELSE
      RAISE NOTICE 'Replication user $REPLICATION_USER already exists';
    END IF;
  END
  \$\$;
EOSQL

# Create standby replication slot if it doesn't exist
psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" <<-EOSQL
  DO \$\$
  BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_replication_slots WHERE slot_name = 'standby_slot') THEN
      PERFORM pg_create_physical_replication_slot('standby_slot');
      RAISE NOTICE 'Created replication slot: standby_slot';
    ELSE
      RAISE NOTICE 'Replication slot standby_slot already exists';
    END IF;
  END
  \$\$;
EOSQL

echo "Replication user setup complete." 