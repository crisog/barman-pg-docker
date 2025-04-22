#!/bin/bash
set -e

# 1) Bring up SSH so Barman can connect:
mkdir -p /root/.ssh
if [ -n "$SSH_PRIVATE_KEY" ]; then
  printf "%s" "$SSH_PRIVATE_KEY" > /root/.ssh/id_rsa
  printf "%s" "$SSH_PUBLIC_KEY"  > /root/.ssh/id_rsa.pub
  printf "%s" "$SSH_PUBLIC_KEY"  > /root/.ssh/authorized_keys
else
  ssh-keygen -t rsa -N '' -f /root/.ssh/id_rsa
  cp /root/.ssh/id_rsa.pub /root/.ssh/authorized_keys
fi
chmod 700 /root/.ssh && chmod 600 /root/.ssh/id_rsa* /root/.ssh/authorized_keys
/usr/sbin/sshd
echo "sshd started"

# 2) If $PGDATA is empty, fetch a fresh base backup via your Barman server:
if [ -z "$(ls -A "$PGDATA")" ]; then
  echo "🍃 PGDATA empty — running Barman remote recover…"
  barman recover \
    --remote-ssh-command "ssh postgres@localhost" \
    --target-time "${TARGET_TIME:-latest}" \
    postgres-source-db latest \
    "$PGDATA"
fi

# 3) Hand off to the normal wrapper → postgres startup
echo "Handing off to wrapper → starting postgres"
exec /usr/local/bin/wrapper.sh "$@"
