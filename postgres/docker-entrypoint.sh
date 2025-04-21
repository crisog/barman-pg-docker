#!/bin/bash
set -e

# ----------------------------
# 1. Synchronous SSH setup
# ----------------------------
setup_ssh() {
  # -- root user
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

  # -- postgres user
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

  # Disable host‑checking for postgres → barman host
  cat <<EOF > /var/lib/postgresql/.ssh/config
Host barman-pg-*
  StrictHostKeyChecking no
  UserKnownHostsFile=/dev/null
EOF
  chmod 600 /var/lib/postgresql/.ssh/config
  chown postgres:postgres /var/lib/postgresql/.ssh/config
}

# ----------------------------
# 2. Ensure WAL‑archive config
# ----------------------------
apply_archive_settings() {
  PG_CONF="$PGDATA/postgresql.conf"
  # Safety: bail if PGDATA isn't initialized
  [ -f "$PG_CONF" ] || return

  # Only append if not already present
  if ! grep -q "^archive_mode = on" "$PG_CONF"; then
    {
      echo ""
      echo "# barman WAL archive settings"
      echo "listen_addresses = '*'"
      echo "wal_level = hot_standby"
      echo "archive_mode = on"
      echo "archive_command = 'rsync -a %p barman@barman-pg:/backup/barman/postgres-source-db/incoming/%f'"
      echo "max_wal_senders = 2"
      echo "max_replication_slots = 2"
    } >> "$PG_CONF"
  fi
}

# ----------------------------
# 3. Start SSHD
# ----------------------------
start_sshd() {
  /usr/sbin/sshd
  echo "sshd started"
}

# ----------------------------
# 4. Exec Railway wrapper → postgres
# ----------------------------
main() {
  setup_ssh
  start_sshd
  apply_archive_settings
  exec /usr/local/bin/wrapper.sh "$@"
}

main "$@"
