#!/bin/bash
set -e

echo "[$(date)] Starting docker-entrypoint.sh"

# Validate PGDATA is set
if [ -z "$PGDATA" ]; then
  echo "[$(date)] ERROR: Missing PGDATA variable" >&2
  exit 1
fi
echo "[$(date)] PGDATA is set to: $PGDATA"

# Function to check if SSH key is valid (contains PEM header)
is_valid_ssh_key() {
  echo "$1" | grep -q "BEGIN.*PRIVATE KEY"
}

customize() {
  echo "[$(date)] Starting customize function"
  
  # Root SSH key setup
  echo "[$(date)] Setting up root SSH keys"
  mkdir -p /root/.ssh
  if [ -n "$SSH_PRIVATE_KEY" ] && is_valid_ssh_key "$SSH_PRIVATE_KEY"; then
    echo "[$(date)] Using provided SSH keys for root"
    echo "$SSH_PRIVATE_KEY" > /root/.ssh/id_rsa
    echo "$SSH_PUBLIC_KEY"  > /root/.ssh/id_rsa.pub
    echo "$SSH_PUBLIC_KEY"  > /root/.ssh/authorized_keys
  else
    echo "[$(date)] Generating new SSH keys for root"
    ssh-keygen -t rsa -N "" -f /root/.ssh/id_rsa
    cp /root/.ssh/id_rsa.pub /root/.ssh/authorized_keys
  fi
  chmod 700 /root/.ssh && chmod 600 /root/.ssh/id_rsa* && chmod 600 /root/.ssh/authorized_keys
  echo "[$(date)] Root SSH setup complete"

  # Postgres user SSH setup
  echo "[$(date)] Setting up postgres user SSH keys"
  su - postgres -c "mkdir -p ~postgres/.ssh
    if [ -n \"$SSH_PRIVATE_KEY\" ] && is_valid_ssh_key \"$SSH_PRIVATE_KEY\"; then
      echo \"[$(date)] Using provided SSH keys for postgres user\"
      echo \"$SSH_PRIVATE_KEY\" > ~postgres/.ssh/id_rsa
      echo \"$SSH_PUBLIC_KEY\"  > ~postgres/.ssh/id_rsa.pub
      echo \"$SSH_PUBLIC_KEY\"  > ~postgres/.ssh/authorized_keys
    else
      echo \"[$(date)] Generating new SSH keys for postgres user\"
      ssh-keygen -t rsa -N \"\" -f ~postgres/.ssh/id_rsa
      cp ~postgres/.ssh/id_rsa.pub ~postgres/.ssh/authorized_keys
    fi
    chmod 700 ~postgres/.ssh && chmod 600 ~postgres/.ssh/id_rsa* && chmod 600 ~postgres/.ssh/authorized_keys"
  echo "[$(date)] Postgres user SSH setup complete"

  # Start SSH daemon
  echo "[$(date)] Starting SSH daemon"
  /usr/sbin/sshd
  echo "[$(date)] SSH daemon started"
  
  echo "[$(date)] Customize function completed"
}

# Run SSH setup in background
echo "[$(date)] Running SSH setup in background"
customize &

# Finally, exec Railway's SSL wrapper (initdb, init-ssl.sh, then postgres)
echo "[$(date)] Executing wrapper.sh: $@"
exec /usr/local/bin/wrapper.sh "$@"