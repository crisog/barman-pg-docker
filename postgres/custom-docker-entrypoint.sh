#!/bin/bash
set -e

# -----------------------------------------------------------------------------
# 1. SSH setup for root and postgres, then start sshd
# -----------------------------------------------------------------------------
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
  chmod 600 /root/.ssh/id_rsa*
  chmod 600 /root/.ssh/authorized_keys

  # postgres
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
    chmod 600 ~/.ssh/id_rsa*
    chmod 600 ~/.ssh/authorized_keys
  '"

  # disable host‑key checking for your Barman host
  cat <<EOF > /var/lib/postgresql/.ssh/config
Host barman-pg-*
  StrictHostKeyChecking no
  UserKnownHostsFile=/dev/null
EOF
  chmod 600 /var/lib/postgresql/.ssh/config
  chown postgres:postgres /var/lib/postgresql/.ssh/config

  # Finally start sshd in the background
  /usr/sbin/sshd
  echo "sshd started"
}

# -----------------------------------------------------------------------------
# 2. Append WAL‑archive settings if they're not already present
# -----------------------------------------------------------------------------
apply_archive_settings() {
  PG_CONF="$PGDATA/postgresql.conf"
  [ -f "$PG_CONF" ] || return

  if ! grep -q "^archive_mode = on" "$PG_CONF"; then
    cat >> "$PG_CONF" <<EOF

# --- barman archive configuration ---
listen_addresses = '*'
wal_level = hot_standby
archive_mode = on
archive_command = 'rsync -a %p barman@barman.railway.internal:/backup/barman/postgres-source-db/incoming/%f'
max_wal_senders = 2
max_replication_slots = 2
EOF
  fi
}

# -----------------------------------------------------------------------------
# 3. Bootstrap everything, then hand off to the wrapper script
# -----------------------------------------------------------------------------
main() {
  # Setup SSH server
  setup_ssh
  apply_archive_settings

  # Now exec the wrapper.sh script, passing along any args (e.g. "postgres")
  echo "Handing off to wrapper script with arguments: $@"
  exec /usr/local/bin/wrapper.sh "$@"
}

main "$@"
