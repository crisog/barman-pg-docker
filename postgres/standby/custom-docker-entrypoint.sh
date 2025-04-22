#!/bin/bash
set -e

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

su postgres -c "mkdir -p ~/.ssh && chmod 700 ~/.ssh"
if [ -n "$SSH_PRIVATE_KEY" ]; then
  su postgres -c "printf '%s' \"$SSH_PRIVATE_KEY\" > ~/.ssh/id_rsa"
  su postgres -c "printf '%s' \"$SSH_PUBLIC_KEY\"  > ~/.ssh/id_rsa.pub"
  su postgres -c "printf '%s' \"$SSH_PUBLIC_KEY\"  > ~/.ssh/authorized_keys"
else
  su postgres -c "cp /root/.ssh/id_rsa* ~/.ssh/"
fi
su postgres -c "chmod 600 ~/.ssh/id_rsa* ~/.ssh/authorized_keys"

cat > /root/.ssh/config <<EOF
Host barman*
  StrictHostKeyChecking no
  UserKnownHostsFile=/dev/null
EOF
chmod 600 /root/.ssh/config

su postgres -c "mkdir -p ~/.ssh && cat /root/.ssh/config > ~/.ssh/config && chmod 600 ~/.ssh/config"

/usr/sbin/sshd
echo "SSH daemon started"

exec /usr/local/bin/wrapper.sh "$@"
