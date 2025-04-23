# Backup Commands

### Restore remote standby
```bash
barman restore --remote-ssh-command "ssh -i ~/.ssh/id_rsa root@standby-pg.railway.internal" --standby-mode pg-primary-db latest /var/lib/postgresql/data
```

### Delete cloud backups
```bash
aws --endpoint-url https://<ACCOUNT_ID>.r2.cloudflarestorage.com \
    s3 rm s3://railway-pg-backup --recursive
```

### Trigger backup
```bash
barman backup pg-primary-db
```
