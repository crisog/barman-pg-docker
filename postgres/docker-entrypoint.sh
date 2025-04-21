#!/bin/bash
set -e

# Validate PGDATA is set
if [ -z "$PGDATA" ]; then
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

  # Postgres user SSH setup - pass environment variables explicitly
  su - postgres -c "
    mkdir -p ~/.ssh
    if [ -n '$SSH_PRIVATE_KEY' ]; then
      echo '$SSH_PRIVATE_KEY' > ~/.ssh/id_rsa
      echo '$SSH_PUBLIC_KEY'  > ~/.ssh/id_rsa.pub
      echo '$SSH_PUBLIC_KEY'  > ~/.ssh/authorized_keys
    else
      ssh-keygen -t rsa -N '' -f ~/.ssh/id_rsa
      cp ~/.ssh/id_rsa.pub ~/.ssh/authorized_keys
    fi
    chmod 700 ~/.ssh && chmod 600 ~/.ssh/id_rsa* && chmod 600 ~/.ssh/authorized_keys
  "

  # Start SSH daemon
  /usr/sbin/sshd
}

# Run SSH setup in background
customize &

# Finally, exec Railway's SSL wrapper (initdb, init-ssl.sh, then postgres)
exec /usr/local/bin/wrapper.sh "$@"