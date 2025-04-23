# Backup & Recovery Guide

A concise set of commands and steps for backing up, restoring, promoting, and verifying PostgreSQL standbys using Barman and Cloudflare R2.

---

## 1. Backup Commands

### Delete a cloud backup (R2)
```bash
aws --endpoint-url https://<ACCOUNT_ID>.r2.cloudflarestorage.com \
    s3 rm s3://railway-pg-backup --recursive
```

### Trigger a manual base backup
```bash
barman backup pg-primary-db
```

---

## 2. Restore Standby

### 2.1 Restore latest backup into standby directory
```bash
barman restore \
  --remote-ssh-command "ssh -i ~/.ssh/id_rsa root@standby-pg.railway.internal" \
  --standby-mode pg-primary-db latest /var/lib/postgresql/data
```
> After running this, start PostgreSQL in **active** mode. The server will come up in standby and begin streaming from the primary.

### 2.2 Point-in-Time Recovery (PITR)
If you need to recover the standby to a specific timestamp instead of the latest WAL:

```bash
barman restore \
  --remote-ssh-command "ssh -i ~/.ssh/id_rsa root@standby-pg.railway.internal" \
  --target-time "2025-04-23 19:10:00" \
  --standby-mode pg-primary-db latest /var/lib/postgresql/data
```

- `--target-time "YYYY-MM-DD HH24:MI:SS"` specifies the exact recovery point. Use UTC or include a timezone offset.
- The restore will stop replay at or before this timestamp.
- After restore, start Postgres in active mode as a standby (it will not stream beyond the target time).

---

## 3. Promote Standby to Primary

### (a) Via SQL
```sql
-- inside psql on the standby
SELECT pg_promote(true, 60);
```

---

## 4. Verify Promotion & Replication

### Check promotion status on standby
```sql
SELECT pg_is_in_recovery();   -- f = primary, t = still standby
```

### Confirm no WAL streaming any longer
> Once promoted, the standby stops streaming from the old primary and begins its own WAL generation on a new timeline.

---

## 5. Post-Promotion Notes

- **Split‑brain risk**: ensure the old primary is shut down or set to read‑only immediately after promotion to avoid divergent writes.
- **Update application**: switch your `DATABASE_URL` or proxy/VIP to the newly promoted host.
- **Reconfigure Barman**: point `streaming_conninfo` at the new primary (via DNS/proxy or editing `/etc/barman.d/pg-primary-db.conf`) and reload the service.

