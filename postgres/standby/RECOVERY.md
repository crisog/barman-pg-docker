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

### Restore latest backup into standby directory
```bash
barman restore \
  --remote-ssh-command "ssh -i ~/.ssh/id_rsa root@standby-pg.railway.internal" \
  --standby-mode pg-primary-db latest /var/lib/postgresql/data
```

> After running this, start PostgreSQL in **active** mode. The server will come up in standby and begin streaming from the primary.

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

