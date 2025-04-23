#!/bin/bash
set -e

BARMAN_USER=barman
BARMAN_PASS=$( echo -n "md5${POSTGRES_PASSWORD}${BARMAN_USER}" \
               | md5sum | cut -d' ' -f1 )

REPL_USER=replicator
REPL_PASS=$( echo -n "md5${POSTGRES_PASSWORD}${REPL_USER}" \
              | md5sum | cut -d' ' -f1 )

psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" <<-EOSQL
  DO \$\$
  BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = '$BARMAN_USER') THEN
      CREATE USER $BARMAN_USER WITH LOGIN REPLICATION PASSWORD '$BARMAN_PASS';
    END IF;
  END
  \$\$;

  -- Grant Barman the backup functions it needs
  GRANT EXECUTE ON FUNCTION pg_backup_start(text, boolean) TO $BARMAN_USER;
  GRANT EXECUTE ON FUNCTION pg_backup_stop(boolean) TO $BARMAN_USER;
  GRANT EXECUTE ON FUNCTION pg_switch_wal() TO $BARMAN_USER;
  GRANT EXECUTE ON FUNCTION pg_create_restore_point(text) TO $BARMAN_USER;

  GRANT pg_read_all_settings TO $BARMAN_USER;
  GRANT pg_read_all_stats    TO $BARMAN_USER;
EOSQL

psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" <<-EOSQL
  DO \$\$
  BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = '$REPL_USER') THEN
      CREATE USER $REPL_USER WITH LOGIN REPLICATION PASSWORD '$REPL_PASS';
    END IF;
  END
  \$\$;
EOSQL

psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "
  ALTER USER \"$POSTGRES_USER\" WITH SUPERUSER PASSWORD '$POSTGRES_PASSWORD';
"

psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "
  GRANT ALL PRIVILEGES ON DATABASE \"$POSTGRES_DB\" TO \"$POSTGRES_USER\";
"

psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" <<-EOSQL
  DO \$\$
  BEGIN
    IF NOT EXISTS (
      SELECT 1 FROM pg_replication_slots WHERE slot_name = 'barman_slot'
    ) THEN
      PERFORM pg_create_physical_replication_slot('barman_slot');
    END IF;
  END
  \$\$;
EOSQL

psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" <<-EOSQL
  DO \$\$
  BEGIN
    IF NOT EXISTS (
      SELECT 1 FROM pg_replication_slots WHERE slot_name = 'standby_slot'
    ) THEN
      PERFORM pg_create_physical_replication_slot('standby_slot');
    END IF;
  END
  \$\$;
EOSQL
