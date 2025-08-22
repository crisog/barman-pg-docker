#!/bin/bash
set -e

setup_ssh() {
  if [ -z "$SSH_PRIVATE_KEY" ] || [ -z "$SSH_PUBLIC_KEY" ]; then
    echo "ERROR: SSH_PRIVATE_KEY and SSH_PUBLIC_KEY environment variables are required but not set"
    exit 1
  fi

  # root
  mkdir -p /root/.ssh
  printf "%s" "$SSH_PRIVATE_KEY" > /root/.ssh/id_ed25519
  printf "%s" "$SSH_PUBLIC_KEY"  > /root/.ssh/id_ed25519.pub
  printf "%s" "$SSH_PUBLIC_KEY"  > /root/.ssh/authorized_keys
  chmod 700 /root/.ssh
  chmod 600 /root/.ssh/id_ed25519* /root/.ssh/authorized_keys

  # postgres user
  su postgres -c "bash -lc '
    mkdir -p ~/.ssh
    printf \"%s\" \"\$SSH_PRIVATE_KEY\" > ~/.ssh/id_ed25519
    printf \"%s\" \"\$SSH_PUBLIC_KEY\"  > ~/.ssh/id_ed25519.pub
    printf \"%s\" \"\$SSH_PUBLIC_KEY\"  > ~/.ssh/authorized_keys
    chmod 700 ~/.ssh
    chmod 600 ~/.ssh/id_ed25519* ~/.ssh/authorized_keys
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

main() {
  setup_ssh
  echo "Handing off to wrapper..."
  exec /usr/local/bin/wrapper.sh "$@"
}

main "$@"
