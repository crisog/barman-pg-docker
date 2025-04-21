#!/bin/bash
set -e

# Ensure PGDATA is set
if [ -z "$PGDATA" ]; then
  echo "Missing PGDATA variable"
  exit 1
fi

function customize {
  # SSH key setup for root
  mkdir -p /root/.ssh
  if [ -n "$SSH_PRIVATE_KEY" ]; then
    echo "$SSH_PRIVATE_KEY" > /root/.ssh/id_rsa
    echo "$SSH_PUBLIC_KEY"  > /root/.ssh/id_rsa.pub
    echo "$SSH_PUBLIC_KEY"  > /root/.ssh/authorized_keys
  else
    ssh-keygen -t rsa -N "" -f /root/.ssh/id_rsa
    cp /root/.ssh/id_rsa.pub /root/.ssh/authorized_keys
  fi
  chmod 700 /root/.ssh
  chmod 644 /root/.ssh/id_rsa.pub
  chmod 600 /root/.ssh/id_rsa
  chmod 600 /root/.ssh/authorized_keys

  # SSH key setup for postgres user
  su - postgres -c "mkdir -p ~postgres/.ssh
    if [ -n \"$SSH_PRIVATE_KEY\" ]; then
      echo \"$SSH_PRIVATE_KEY\" > ~postgres/.ssh/id_rsa
      echo \"$SSH_PUBLIC_KEY\"  > ~postgres/.ssh/id_rsa.pub
      echo \"$SSH_PUBLIC_KEY\"  > ~postgres/.ssh/authorized_keys
    else
      ssh-keygen -t rsa -N \"\" -f ~postgres/.ssh/id_rsa
      cp ~postgres/.ssh/id_rsa.pub ~postgres/.ssh/authorized_keys
    fi
    chmod 700 ~postgres/.ssh
    chmod 644 ~postgres/.ssh/id_rsa.pub
    chmod 600 ~postgres/.ssh/id_rsa
    chmod 600 ~postgres/.ssh/authorized_keys"

  # Start SSH daemon
  /usr/sbin/sshd
}

# Run customization in background
customize &

# Hand off to Railway SSL wrapper (will init SSL in PGDATA and start Postgres)
exec /usr/local/bin/wrapper.sh "$@"