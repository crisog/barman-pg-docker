# PostgreSQL Point-in-Time Recovery Guide

Guide for Point-in-Time Recovery (PITR) using Barman on Railway with Cloudflare R2.

**Use Cases**: 
- Recover from accidental data deletion
- Restore before corruption or bad deployment
- Create database state at specific timestamp

**Production Architecture**:
- **Primary + Hot Standby**: For instant failover
- **PITR Service**: Duplicate standby service for point-in-time recovery (doesn't affect production replication)

**Workflow**: Duplicate standby service → idle mode → barman restore → automatic primary

---

## 1. Backup Management

> **Note**: All barman commands require connecting to the barman service first with `railway ssh barman`. PostgreSQL verification commands connect directly to the exposed database port.

### Create manual backup
```bash
su - barman -c "barman backup pg-primary-db"
```

### Delete cloud backups (Cloudflare R2)
```bash
# Replace YOUR_ACCOUNT_ID with actual Cloudflare account ID
aws --endpoint-url https://YOUR_ACCOUNT_ID.r2.cloudflarestorage.com \
    s3 rm s3://YOUR_BUCKET_NAME --recursive
```

### List available backups
```bash
su - barman -c "barman list-backup pg-primary-db"
```

---

## 2. Point-in-Time Recovery Process

### Step 1: Create PITR Service
In Railway dashboard:
1. **Duplicate your standby service** (don't use primary service)
2. **Rename** to something like "pitr-recovery" 
3. **Important**: This keeps your production hot standby untouched

### Step 2: Configure PITR service for restore
In Railway dashboard for the new PITR service:
1. Set environment variables:
   - `MODE=idle`
   - **Remove `PRIMARY_HOST`** (critical - prevents replication attempts)
   - Keep `SSH_PRIVATE_KEY` and `SSH_PUBLIC_KEY` (for barman access)
   - Keep `POSTGRES_PASSWORD`
2. Redeploy the service
3. Service starts in idle mode (SSH accessible, PostgreSQL not running)

### Step 3: Determine recovery target
```bash
# Check available backups and WAL timeline
su - barman -c "barman show-backup pg-primary-db latest"
su - barman -c "barman list-backup pg-primary-db"
```

### Step 4: Clear existing data and restore to specific time
```bash
# Clear target data directory
su - barman -c "ssh -i /var/lib/barman/.ssh/id_rsa root@target-service.railway.internal 'rm -rf /var/lib/postgresql/data/pgdata/*'"

# Restore to specific timestamp (UTC format)
su - barman -c "barman restore \
  --remote-ssh-command 'ssh -i /var/lib/barman/.ssh/id_rsa root@target-service.railway.internal' \
  --target-time '2025-04-23 19:10:00' \
  pg-primary-db latest /var/lib/postgresql/data/pgdata"
```

### Step 5: Activate as standalone primary
In Railway dashboard for PITR service:
1. Set environment variables:
   - `MODE=active`
   - **Ensure `PRIMARY_HOST` is not set** (runs as standalone primary)
   - Keep `POSTGRES_PASSWORD`
2. Redeploy the service
3. **No promotion needed** - PostgreSQL automatically starts as primary

### Step 6: Verify recovery point
```bash
# Connect to recovered database and verify it's a primary
psql -h pitr-host -p 5432 -U postgres -d your_db -c "SELECT pg_is_in_recovery();"
# Should return: f (false = primary, ready for writes)

# Check recovery timestamp and data
psql -h pitr-host -p 5432 -U postgres -d your_db -c "SELECT pg_postmaster_start_time();"
psql -h pitr-host -p 5432 -U postgres -d your_db -c "SELECT now();"

# Test write access (confirms it's primary)
psql -h pitr-host -p 5432 -U postgres -d your_db -c "CREATE TABLE recovery_test (id int);"
```

---

## 3. Verification Commands

### Check database status
```bash
# Check if database is in recovery mode
psql -h target-host -p 5432 -U postgres -d your_db -c "SELECT pg_is_in_recovery();"

# Check database start time
psql -h target-host -p 5432 -U postgres -d your_db -c "SELECT pg_postmaster_start_time();"

# Check database size and basic connectivity
psql -h target-host -p 5432 -U postgres -d your_db -c "SELECT pg_database_size(current_database());"
```

### Check backup status
```bash
# List all backups
su - barman -c "barman list-backup pg-primary-db"

# Check specific backup
su - barman -c "barman show-backup pg-primary-db BACKUP_ID"

# Verify backup integrity
su - barman -c "barman check pg-primary-db"
```

### Monitor logs
```bash
# Check Railway service logs in dashboard
# Or connect to services and view logs:

# Barman service logs
tail -f /var/log/barman/barman.log

# PostgreSQL service logs (if SSH access available)
tail -f /var/lib/postgresql/data/pgdata/log/postgresql-*.log
```

---

## 4. Making PITR Instance the New Primary

If you want to replace your production primary with the recovered data:

### Step 1: Update Application Connections
```bash
# Update your app's DATABASE_URL to point to PITR instance
DATABASE_URL=postgresql://user:pass@pitr-host:5432/dbname
```

### Step 2: Reconfigure Barman
In Railway dashboard for barman service:
```bash
POSTGRES_HOST=pitr-service.railway.internal  # Point to PITR instance
```
Redeploy barman service.

### Step 3: Shutdown Old Infrastructure
1. **Stop old primary service** (prevent split-brain)
2. **Stop old standby service** (no longer needed)
3. **Verify barman connects** to new primary

### Step 4: Optional - Create New Hot Standby
1. **Duplicate the PITR service** (now your primary)
2. **Configure for replication**: Set `PRIMARY_HOST=pitr-service.railway.internal`
3. **Deploy** - it will automatically stream from your new primary

---

## 5. Railway Environment Configuration

### PITR Service Environment Variables
```bash
# Phase 1: Idle mode (ready for restore)
MODE=idle
SSH_PRIVATE_KEY=<your_ssh_private_key>
SSH_PUBLIC_KEY=<your_ssh_public_key>
POSTGRES_PASSWORD=<matching_primary_password>
# DO NOT SET PRIMARY_HOST

# Phase 2: Active standalone primary (after restore)
MODE=active
POSTGRES_PASSWORD=<matching_primary_password>
# DO NOT SET PRIMARY_HOST (this makes it standalone primary)
```

### Critical Notes
- **Always duplicate standby service, never primary service**
- **Never set `PRIMARY_HOST`** for PITR instances (keeps them standalone)
- **No promotion command needed** - automatic primary when no `PRIMARY_HOST`
- **Production replication stays untouched** during PITR process

---

## 6. Troubleshooting

### Common Issues
1. **SSH connection fails**: Verify SSH keys match between barman and target services
2. **Restore fails**: Check target service is in `MODE=idle` and data directory is clear
3. **Database won't start**: Verify `POSTGRES_PASSWORD` matches primary and `PRIMARY_HOST` is unset for standalone

### Recovery Validation
- [ ] Target service shows healthy status in Railway dashboard  
- [ ] Database accepts connections on expected hostname
- [ ] `pg_is_in_recovery()` returns `false` (standalone mode)
- [ ] Data appears at expected recovery timestamp
- [ ] Application can connect and query data

### Rollback
If recovery fails:
1. Set `MODE=idle` and redeploy
2. Clear data directory and retry with different timestamp
3. Verify data integrity before pointing applications to recovered instance

