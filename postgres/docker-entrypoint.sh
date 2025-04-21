#!/bin/bash
set -e

# Validate PGDATA is set
if [ -z "$PGDATA" ]; then
  echo "Missing PGDATA variable" >&2
  exit 1
fi

customize() {
  # Root SSH key setup
  mkdir -p /root/.ssh
  if [ -n "$SSH_PRIVATE_KEY" ]; then
    echo "$SSH_PRIVATE_KEY" > /root/.ssh/id_rsa
    echo "$SSH_PUBLIC_KEY"  > /root/.ssh/id_rsa.pub
    echo "$SSH_PUBLIC_KEY"  > /root/.ssh/authorized_keys
  else
    ssh-keygen -t rsa -N "" -f /root/.ssh/id_rsa
    cp /root/.ssh/id_rsa.pub /root/.ssh/authorized_keys
  fi
  chmod 700 /root/.ssh && chmod 600 /root/.ssh/id_rsa* && chmod 600 /root/.ssh/authorized_keys

  # Postgres user SSH setup
  su - postgres -c "mkdir -p ~postgres/.ssh
    if [ -n \"$SSH_PRIVATE_KEY\" ]; then
      echo \"$SSH_PRIVATE_KEY\" > ~postgres/.ssh/id_rsa
      echo \"$SSH_PUBLIC_KEY\"  > ~postgres/.ssh/id_rsa.pub
      echo \"$SSH_PUBLIC_KEY\"  > ~postgres/.ssh/authorized_keys
    else
      ssh-keygen -t rsa -N \"\" -f ~postgres/.ssh/id_rsa
      cp ~postgres/.ssh/id_rsa.pub ~postgres/.ssh/authorized_keys
    fi
    chmod 700 ~postgres/.ssh && chmod 600 ~postgres/.ssh/id_rsa* && chmod 600 ~postgres/.ssh/authorized_keys"

  # Start SSH daemon
  /usr/sbin/sshd
}

# Run SSH setup in background
customize &

# Finally, exec Railway’s SSL wrapper (initdb, init-ssl.sh, then postgres)
exec /usr/local/bin/wrapper.sh "$@"