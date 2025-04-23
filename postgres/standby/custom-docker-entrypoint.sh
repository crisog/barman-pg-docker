#!/bin/bash
set -e

hash_password() {
    local password="$1"
    local username="$2"
    echo -n "md5${password}${username}" | md5sum | cut -d' ' -f1
}

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
  
  local REPLICATION_PASSWORD_HASH=$(hash_password "${POSTGRES_PASSWORD:-postgres}" "$REPLICATION_USER")

  echo "Setting up replication configuration..."

  cat > "$PGDATA/postgresql.auto.conf" <<EOF
# Replication configuration
primary_conninfo = 'host=$PRIMARY_HOST user=$REPLICATION_USER password=$REPLICATION_PASSWORD_HASH application_name=standby'
restore_command = ''
primary_slot_name = 'standby_slot'
EOF

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

  setup_custom_config

  setup_replication

  setup_ssl

  echo "Active mode: starting Postgres"
  echo "Handing off to wrapper…"
  exec /usr/local/bin/wrapper.sh "$@"
}

main "$@"