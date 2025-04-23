#!/bin/bash
set -e

# regenerate certs if needed (optional)
SSL_DIR="$PGDATA/certs"
INIT_SSL="/docker-entrypoint-initdb.d/03-init-ssl.sh"
PG_CONF="$PGDATA/postgresql.conf"

# Always ensure the certificates directory exists
mkdir -p "$SSL_DIR"
chown postgres:postgres "$SSL_DIR"

# Check if we need to create or regenerate certificates
if [ ! -f "$SSL_DIR/server.crt" ]; then
  echo "SSL certificates not found - generating new certificates..."
  bash "$INIT_SSL"
elif ! openssl x509 -noout -checkend 2592000 -in "$SSL_DIR/server.crt"; then
  echo "Regenerating expiring SSL certificates..."
  bash "$INIT_SSL"
fi

# force local socket usage
unset PGHOST
unset PGPORT

# hand off to upstream entrypoint + server
exec /usr/local/bin/docker-entrypoint.sh "$@"
