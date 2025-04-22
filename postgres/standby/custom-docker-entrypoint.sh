#!/bin/bash
set -e

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

main() {
  setup_ssh

  # Determine run mode: idle (no Postgres) or active (start Postgres)
  mode="${MODE:-idle}"
  if [ "$mode" = "idle" ]; then
    echo "Idle mode: setup complete, waiting for remote restore via SSH"
    # keep container alive without starting Postgres
    exec tail -f /dev/null
  fi

  echo "Active mode: starting Postgres"
  echo "Handing off to wrapper..."
  exec /usr/local/bin/wrapper.sh "$@"
}

main "$@"
