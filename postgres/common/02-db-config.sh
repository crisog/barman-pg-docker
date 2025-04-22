#!/bin/bash
set -e

BARMAN_USER=barman
BARMAN_PASS=$(echo -n "md5${POSTGRES_PASSWORD}${BARMAN_USER}" | md5sum | cut -d' ' -f1)

psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" <<-EOSQL
  -- Create the barman user with login and replication privileges
  CREATE USER $BARMAN_USER WITH LOGIN REPLICATION PASSWORD '$BARMAN_PASS';
  -- Grant necessary backup role (using pg_backup role from PG16+)
  GRANT pg_backup TO $BARMAN_USER;
EOSQL

psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "
  ALTER USER \"$POSTGRES_USER\" WITH SUPERUSER PASSWORD '$POSTGRES_PASSWORD';
"
psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "
  GRANT ALL PRIVILEGES ON DATABASE \"$POSTGRES_DB\" TO \"$POSTGRES_USER\";
"

# Create replication slot if it doesn't exist
psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "\
  DO \$\$ \
  BEGIN \
    IF NOT EXISTS (SELECT 1 FROM pg_replication_slots WHERE slot_name = 'barman_slot') THEN \
      PERFORM pg_create_physical_replication_slot('barman_slot'); \
    END IF; \
  END \$\$; \
"
