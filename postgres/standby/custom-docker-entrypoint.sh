#!/bin/bash
set -e

setup_ssh() {
  mkdir -p /root/.ssh
  if [ -n "$SSH_PRIVATE_KEY" ]; then
    printf "%s" "$SSH_PRIVATE_KEY" > /root/.ssh/id_rsa
    printf "%s" "$SSH_PUBLIC_KEY"  > /root/.ssh/id_rsa.pub
    printf "%s" "$SSH_PUBLIC_KEY"  > /root/.ssh/authorized_keys
  else
    ssh-keygen -t rsa -N '' -f /root/.ssh/id_rsa
    cp /root/.ssh/id_rsa.pub /root/.ssh/authorized_keys
  fi
  chmod 700 /root/.ssh
  chmod 600 /root/.ssh/id_rsa* /root/.ssh/authorized_keys

  su postgres -c "bash -lc '
    mkdir -p ~/.ssh
    if [ -n \"\$SSH_PRIVATE_KEY\" ]; then
      printf \"%s\" \"\$SSH_PRIVATE_KEY\" > ~/.ssh/id_rsa
      printf \"%s\" \"\$SSH_PUBLIC_KEY\"  > ~/.ssh/id_rsa.pub
      printf \"%s\" \"\$SSH_PUBLIC_KEY\"  > ~/.ssh/authorized_keys
    else
      ssh-keygen -t rsa -N \"\" -f ~/.ssh/id_rsa
      cp ~/.ssh/id_rsa.pub ~/.ssh/authorized_keys
    fi
    chmod 700 ~/.ssh
    chmod 600 ~/.ssh/id_rsa* ~/.ssh/authorized_keys
  '"

  cat > /var/lib/postgresql/.ssh/config <<EOF
Host barman.railway.internal barman*
  StrictHostKeyChecking no
  UserKnownHostsFile=/dev/null
EOF
  chmod 600 /var/lib/postgresql/.ssh/config
  chown postgres:postgres /var/lib/postgresql/.ssh/config

  /usr/sbin/sshd
  echo "sshd started"
}

setup_custom_config() {
  if [ -f "/docker-entrypoint-initdb.d/01-init-custom-config.sh" ]; then
    echo "Running custom config script..."
    bash /docker-entrypoint-initdb.d/01-init-custom-config.sh
  fi
}

setup_replication() {
  local PRIMARY_HOST=${PRIMARY_HOST:-postgres-primary}
  local REPLICATION_USER=${REPLICATION_USER:-replicator}
  
  # Use separate REPLICATOR_PASSWORD for replication authentication
  local REPLICATION_PASSWORD="${REPLICATOR_PASSWORD}"
  
  if [ -z "$REPLICATION_PASSWORD" ]; then
    echo "ERROR: REPLICATOR_PASSWORD not set. Cannot configure replication."
    exit 1
  fi

  echo "Setting up replication configuration..."

  # Check if data directory is empty (needs initial backup)
  if [ ! -f "$PGDATA/PG_VERSION" ]; then
    echo "No existing data found. Running pg_basebackup from primary..."
    
    # Create .pgpass file for authentication
    echo "$PRIMARY_HOST:5432:*:$REPLICATION_USER:$REPLICATION_PASSWORD" > ~/.pgpass
    chmod 0600 ~/.pgpass
    
    # Run pg_basebackup to get initial data
    pg_basebackup -h "$PRIMARY_HOST" -p 5432 -U "$REPLICATION_USER" -D "$PGDATA" -R -X stream -S standby_slot
    
    # Clean up .pgpass
    rm -f ~/.pgpass
    
    echo "pg_basebackup completed successfully."
  else
    echo "Existing data found, skipping pg_basebackup."
  fi

  # Ensure standby.signal file exists (required for PostgreSQL 12+)
  touch "$PGDATA/standby.signal"

  # Update replication configuration
  cat >> "$PGDATA/postgresql.auto.conf" <<EOF

# Replication configuration
primary_conninfo = 'host=$PRIMARY_HOST port=5432 user=$REPLICATION_USER password=$REPLICATION_PASSWORD application_name=standby'
primary_slot_name = 'standby_slot'
restore_command = ''
EOF

  # Set proper ownership
  chown -R postgres:postgres "$PGDATA"

  echo "Replication configuration complete."
}

setup_ssl() {
  SSL_DIR="$PGDATA/certs"
  INIT_SSL="/docker-entrypoint-initdb.d/03-init-ssl.sh"

  mkdir -p "$SSL_DIR"
  chown postgres:postgres "$SSL_DIR"

  if [ ! -f "$SSL_DIR/server.crt" ] \
     || ! openssl x509 -noout -checkend 2592000 -in "$SSL_DIR/server.crt"; then
    echo "Generating (or regenerating) SSL certificates…"
    bash "$INIT_SSL"
  fi
}

main() {
  setup_ssh

  mode="${MODE:-idle}"
  if [ "$mode" = "idle" ]; then
    echo "Idle mode: awaiting remote restore via SSH"
    exec tail -f /dev/null
  fi

  # Only set up replication if PRIMARY_HOST is specified
  if [ -n "$PRIMARY_HOST" ]; then
    echo "PRIMARY_HOST specified: setting up as streaming standby"
    setup_replication
  else
    echo "No PRIMARY_HOST: running as standalone instance"
    # For standalone, ensure we don't have standby.signal
    rm -f "$PGDATA/standby.signal"
  fi

  setup_custom_config
  setup_ssl

  echo "Active mode: starting Postgres"
  echo "Handing off to wrapper…"
  exec /usr/local/bin/wrapper.sh "$@"
}

main "$@"