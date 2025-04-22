#!/bin/bash
set -euo pipefail

# ── Required ENV ────────────────────────────────────────────────
#   BARMAN_HOST         e.g. barman.railway.internal
#   SSH_PRIVATE_KEY     your PEM‐formatted key
#   SSH_PUBLIC_KEY      optional, for no‐prompt host verification
#   PRIMARY_HOST        your primary’s hostname for streaming (if used)
#   POSTGRES_PASSWORD  (the password you used when creating the barman user)
# ── Optional ────────────────────────────────────────────────────
#   RECOVERY_TIME       "YYYY-MM-DD HH:MM:SS" for PITR

PGDATA=${PGDATA:-/var/lib/postgresql/data}

# ── 0) Recompute the actual Barman password hash ───────────────────────
#    (matches how you did it in 02-db-config.sh)
BARMAN_PASS=$(echo -n "md5${POSTGRES_PASSWORD}barman" \
              | md5sum | cut -d' ' -f1)

# ── 1) Minimal Barman config for client recover ───────────────────────
mkdir -p /etc/barman.d

cat > /etc/barman.conf <<EOF
[barman]
barman_home = /var/lib/barman
log_level = DEBUG
compression = gzip
reuse_backup = link
wal_retention_policy = main
retention_policy_mode = auto
EOF

cat > /etc/barman.d/postgres-source-db.conf <<EOF
[postgres-source-db]
description = Primary PostgreSQL on Railway
conninfo = host=${BARMAN_HOST} user=barman dbname=postgres password=${BARMAN_PASS}
ssh_command = ssh postgres@${BARMAN_HOST}
backup_method = rsync
incoming_wals_directory = /backup/barman/postgres-source-db/incoming
streaming_archiver = off
archiver = on
retention_policy = RECOVERY WINDOW OF 7 days
wal_retention_policy = main
EOF

chmod 600 /etc/barman.conf \
       /etc/barman.d/postgres-source-db.conf

# ── 2) SSH key setup for outbound to Barman ──────────────────────────
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

# ── 3) Recover base backup + WAL (either PITR or latest) ──────────────
if [ -n "${RECOVERY_TIME-}" ] || [ -z "$(ls -A "$PGDATA")" ]; then
  echo "[standby] Running Barman recovery..."

  # sanity check
  barman check postgres-source-db \
    --remote-ssh-command "ssh -i /root/.ssh/id_rsa postgres@${BARMAN_HOST}"

  # recover at RECOVERY_TIME or just latest
  if [ -n "${RECOVERY_TIME-}" ]; then
    barman recover \
      --remote-ssh-command "ssh -i /root/.ssh/id_rsa postgres@${BARMAN_HOST}" \
      --target-time "$RECOVERY_TIME" \
      postgres-source-db latest \
      "$PGDATA"
  else
    barman recover \
      --remote-ssh-command "ssh -i /root/.ssh/id_rsa postgres@${BARMAN_HOST}" \
      postgres-source-db latest \
      "$PGDATA"
  fi

  # fix permissions
  chown -R postgres:postgres "$PGDATA"
  echo "[standby] Recovery finished."
fi

# ── 4) Hand off to your wrapper, which calls docker-entrypoint.sh ────
exec /usr/local/bin/wrapper.sh postgres
