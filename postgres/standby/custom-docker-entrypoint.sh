#!/bin/bash
set -e

mkdir -p /root/.ssh
if [ -n "$SSH_PRIVATE_KEY" ]; then
  printf "%s" "$SSH_PRIVATE_KEY" > /root/.sh  h/id_rsa
  printf "%s" "$SSH_PUBLIC_KEY"  > /root/.ssh/id_rsa.pub
  printf "%s" "$SSH_PUBLIC_KEY"  > /root/.ssh/authorized_keys
else
  ssh-keygen -t rsa -N '' -f /root/.ssh/id_rsa
  cp /root/.ssh/id_rsa.pub /root/.ssh/authorized_keys
fi
chmod 700 /root/.ssh && chmod 600 /root/.ssh/id_rsa* /root/.ssh/authorized_keys
/usr/sbin/sshd
echo "sshd started"

case "$1" in

  idle)
    echo "➜ Standby idle. To PITR, set COMMAND to 'recover' and RECOVERY_TIME, then redeploy."
    tail -f /dev/null
    ;;

  recover)
    echo "⟳ Starting recovery: base backup + WAL replay up to ${RECOVERY_TIME:-latest}"

    rm -rf "${PGDATA:?}"/*

    barman recover \
      --remote-ssh-command "ssh postgres@localhost" \
      --target-time "${RECOVERY_TIME:-latest}" \
      postgres-source-db latest \
      "$PGDATA"

    cat >> "$PGDATA/postgresql.auto.conf" <<EOF
# fetch archived WALs from your R2 bucket
restore_command = 'barman-cloud-wal-restore \
  --cloud-provider aws-s3 \
  --endpoint-url https://${R2_ACCOUNT_ID}.r2.cloudflarestorage.com \
  --no-partial \
  s3://${R2_BUCKET}/wal-archives \
  postgres-source-db \
  %f %p'
recovery_target_time   = '${RECOVERY_TIME:-latest}'
recovery_target_action = 'pause'
EOF

    touch "$PGDATA/recovery.signal"
    echo "✅ Recovery config written; launching Postgres in standby mode…"

    exec /usr/local/bin/wrapper.sh postgres
    ;;

  *)
    echo "Unknown command: $1"
    exit 1
    ;;
esac
