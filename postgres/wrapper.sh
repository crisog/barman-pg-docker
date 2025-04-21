#!/bin/bash
set -e

# regenerate certs if needed (optional)
SSL_DIR="/var/lib/postgresql/data/certs"
INIT_SSL="/docker-entrypoint-initdb.d/03-init-ssl.sh"
PG_CONF="$PGDATA/postgresql.conf"

# if existing cert is invalid or expiring soon, re-run SSL script
if [ -f "$SSL_DIR/server.crt" ]; then
  if ! openssl x509 -noout -checkend 2592000 -in "$SSL_DIR/server.crt"; then
    echo "Regenerating expiring SSL certificates..."
    bash "$INIT_SSL"
  fi
fi

# force local socket usage
unset PGHOST
unset PGPORT

# hand off to upstream entrypoint + server
exec /usr/local/bin/docker-entrypoint.sh "$@"
