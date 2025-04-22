#!/bin/bash
set -euo pipefail

# ── Required ENV ────────────────────────────────────────────────
#   BARMAN_HOST       e.g. barman.railway.internal
#   SSH_PRIVATE_KEY   your PEM‐formatted key
#   SSH_PUBLIC_KEY    optional, for no‑prompt host verification
#   POSTGRES_PASSWORD (the password you used when creating the barman user)
# ── Optional ────────────────────────────────────────────────────
#   RECOVERY_TIME     "YYYY-MM-DD HH:MM:SS" for PITR

PGDATA=${PGDATA:-/var/lib/postgresql/data}

# ── 0) Recompute the real barman password hash ───────────────────
BARMAN_PASS=$(echo -n "md5${POSTGRES_PASSWORD}barman" \
              | md5sum | cut -d' ' -f1)

# ── 1) Build minimal Barman config ───────────────────────────────
mkdir -p /etc/barman.d
chmod 755 /etc/barman.d

cat > /etc/barman.conf <<EOF
[barman]
barman_home = /var/lib/barman
configuration_files_directory = /etc/barman.d
log_level = DEBUG
EOF

cat > /etc/barman.d/postgres-source-db.conf <<EOF
[postgres-source-db]
description = Primary PostgreSQL on Railway
conninfo = host=${BARMAN_HOST} user=barman dbname=postgres password=${BARMAN_PASS}
ssh_command = ssh postgres@${BARMAN_HOST}
backup_method = rsync
EOF

chmod 600 /etc/barman.conf /etc/barman.d/postgres-source-db.conf

# ── 2) SSH key setup for outbound to Barman ──────────────────────
mkdir -p /root/.ssh
if [ -n "${SSH_PRIVATE_KEY-}" ]; then
  printf "%s" "$SSH_PRIVATE_KEY" > /root/.ssh/id_rsa
  printf "%s" "$SSH_PUBLIC_KEY"  > /root/.ssh/authorized_keys
else
  ssh-keygen -t rsa -N '' -f /root/.ssh/id_rsa
  cp /root/.ssh/id_rsa.pub /root/.ssh/authorized_keys
fi
chmod 700 /root/.ssh
chmod 600 /root/.ssh/id_rsa* /root/.ssh/authorized_keys

cat > /root/.ssh/config <<EOF
Host ${BARMAN_HOST}
  StrictHostKeyChecking no
  UserKnownHostsFile=/dev/null
EOF
chmod 600 /root/.ssh/config

# ── 3) Ensure PGDATA exists ──────────────────────────────────────
mkdir -p "${PGDATA}"

# ── 4) Recover if PITR requested or PGDATA is empty ──────────────
if [ -n "${RECOVERY_TIME-}" ] || [ -z "$(ls -A "${PGDATA}")" ]; then
  echo "[standby] Running Barman recovery..."

  # Make sure barman home directory exists
  mkdir -p /var/lib/barman

  # List available servers for diagnostic purposes
  barman list-server

  # sanity‑check: uses ssh_command from /etc/barman.d
  barman check postgres-source-db

  # recover at RECOVERY_TIME (if set) or latest
  if [ -n "${RECOVERY_TIME-}" ]; then
    barman recover \
      --target-time "$RECOVERY_TIME" \
      postgres-source-db latest \
      "$PGDATA"
  else
    barman recover \
      postgres-source-db latest \
      "$PGDATA"
  fi

  chown -R postgres:postgres "$PGDATA"
  echo "[standby] Recovery finished."
fi

# ── 5) Hand off to wrapper (which calls docker-entrypoint.sh) ────
exec /usr/local/bin/wrapper.sh postgres