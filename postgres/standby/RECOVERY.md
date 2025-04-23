## Backup Commands

```bash
barman restore --remote-ssh-command "ssh -i ~/.ssh/id_rsa root@standby-pg.railway.internal" --standby-mode pg-primary-db latest /var/lib/postgresql/data
```