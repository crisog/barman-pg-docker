#!/bin/bash
set -e

# Function to hash passwords the same way as the DB init script
hash_password() {
    local password="$1"
    local username="$2"
    echo -n "md5${password}${username}" | md5sum | cut -d' ' -f1
}

setup_ssh() {
  # root
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

  # postgres user
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

  # disable host‑key checking for barman host
  cat > /var/lib/postgresql/.ssh/config <<EOF
Host barman.railway.internal barman*
  StrictHostKeyChecking no
  UserKnownHostsFile=/dev/null
EOF
  chmod 600 /var/lib/postgresql/.ssh/config
  chown postgres:postgres /var/lib/postgresql/.ssh/config

  # finally start sshd (it will daemonize itself)
  /usr/sbin/sshd
  echo "sshd started"
}

setup_custom_config() {
  # Manually run the init script since recovery mode skips init scripts
  if [ -f "/docker-entrypoint-initdb.d/01-init-custom-config.sh" ]; then
    echo "Running custom config script..."
    bash /docker-entrypoint-initdb.d/01-init-custom-config.sh
  fi
}

setup_replication_user() {
  # Setup the replication user on the standby server
  # This prepares it for eventual promotion to primary
  if [ -f "/usr/local/bin/setup-replication-user.sh" ]; then
    echo "Setting up replication user for future primary role..."
    bash /usr/local/bin/setup-replication-user.sh
    echo "Replication user setup complete"
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

main() {
  setup_ssh

  # Determine run mode: idle (no Postgres) or active (start Postgres)
  mode="${MODE:-idle}"
  if [ "$mode" = "idle" ]; then
    echo "Idle mode: setup complete, waiting for remote restore via SSH"
    # keep container alive without starting Postgres
    exec tail -f /dev/null
  fi

  setup_custom_config
  
  # If the PREPARE_FOR_PROMOTION env var is set, configure the standby like a primary
  if [ "${PREPARE_FOR_PROMOTION:-false}" = "true" ]; then
    echo "Preparing standby for potential promotion to primary..."
    setup_replication_user
  fi
  
  setup_replication

  echo "Active mode: starting Postgres"
  echo "Handing off to wrapper..."
  exec /usr/local/bin/wrapper.sh "$@"
}

main "$@"
