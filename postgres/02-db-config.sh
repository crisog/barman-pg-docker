# 02-db-config.sh
#!/bin/bash
set -e

echo "[$(date)] Starting 02-db-config.sh"

# Create a superuser 'barman' for backups, with an MD5‐hashed password
# (uses POSTGRES_PASSWORD + username for the md5 hash prefix)
echo "[$(date)] Creating barman superuser"
BARMAN_USER=barman
BARMAN_PASS=$(echo -n "md5${POSTGRES_PASSWORD}${BARMAN_USER}" | md5sum | cut -d' ' -f1)

psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" <<-EOSQL
  CREATE USER $BARMAN_USER WITH SUPERUSER PASSWORD '$BARMAN_PASS';
  GRANT ALL PRIVILEGES ON DATABASE "$POSTGRES_DB" TO $BARMAN_USER;
EOSQL
echo "[$(date)] Successfully created barman user and granted privileges"

# Ensure your main user is superuser and has the right password/privileges
echo "[$(date)] Setting up main Postgres user privileges"
psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "
  ALTER USER \"$POSTGRES_USER\" WITH SUPERUSER PASSWORD '$POSTGRES_PASSWORD';
"
psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "
  GRANT ALL PRIVILEGES ON DATABASE \"$POSTGRES_DB\" TO \"$POSTGRES_USER\";
"
echo "[$(date)] Successfully set up main Postgres user privileges"

echo "[$(date)] Completed 02-db-config.sh"