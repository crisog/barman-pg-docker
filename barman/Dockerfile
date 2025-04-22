# Dockerfile for Barman

# Basic Setup
FROM debian:bookworm-slim

# Build args for R2 and AWS credentials (pass at build or runtime)
ARG R2_ACCOUNT_ID
ARG R2_BUCKET

ENV R2_ACCOUNT_ID=${R2_ACCOUNT_ID}
ENV R2_BUCKET=${R2_BUCKET}

RUN apt-get update && apt-get install -y --no-install-recommends wget gnupg2 cron openssh-server openssh-client && rm -rf /var/lib/apt/lists/*
RUN sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt/ bookworm-pgdg main" > /etc/apt/sources.list.d/pgdg.list' \ 
	&& (wget --no-check-certificate --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add - || wget --no-check-certificate --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor > /etc/apt/trusted.gpg.d/apt.postgresql.org.gpg) \ 
	&& apt-get update && apt-get install -y barman \ 	
	&& rm -rf /var/lib/apt/lists/*

# SSH Setup
RUN mkdir -p /var/run/sshd
RUN echo 'root:password' | chpasswd
RUN sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config
RUN echo "Host pg-docker.railway.internal pg-docker*" >> /etc/ssh/ssh_config && echo " StrictHostKeyChecking no" >> /etc/ssh/ssh_config

# SSH login fix. Otherwise user is kicked off after login
RUN sed 's@session\s*required\s*pam_loginuid.so@session optional pam_loginuid.so@g' -i /etc/pam.d/sshd
ENV NOTVISIBLE "in users profile"
RUN echo "export VISIBLE=now" >> /etc/profile

# Barman Setup
# Create base SSH directories but don't rely on pre-existing keys
RUN mkdir -p ~/.ssh && chmod 700 ~/.ssh && touch ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys \ 
	&& chown -R barman: /etc/barman.conf \ 
	&& echo "" >> /etc/cron.d/barman \ 
	&& echo "0 3 * * * barman /usr/bin/barman backup postgres-source-db" > /etc/cron.d/barmanpgbackup && echo "" >> /etc/cron.d/barmanpgbackup \ 
	&& touch /etc/crontab /etc/cron.*/* \
	&& sed -i.bak 's_/var/lib/barman_/backup/barman_' /etc/barman.conf \ 
	&& sed -i.bak 's_^.*compression = gzip_compression = gzip_' /etc/barman.conf \ 
	&& sed -i.bak 's-^.*immediate_checkpoint = false-immediate_checkpoint = true-' /etc/barman.conf \ 
	&& sed -i.bak 's-^.*basebackup_retry_times = 0-basebackup_retry_times = 3-' /etc/barman.conf \ 
	&& sed -i.bak 's-^.*basebackup_retry_sleep = 30-basebackup_retry_sleep = 30-' /etc/barman.conf \ 
	&& sed -i.bak 's-^.*last_backup_maximum_age =-last_backup_maximum_age = 1 DAYS-' /etc/barman.conf \ 
	&& sed -i.bak 's-^.*minimum_redundancy = 1-minimum_redundancy = 1-' /etc/barman.conf \ 
	&& sed -i.bak 's-^.*retention_policy =$-retention_policy = RECOVERY WINDOW OF 1 WEEKS-' /etc/barman.conf \ 
	&& sed -i.bak 's-^.*log_level = INFO$-log_level = DEBUG-' /etc/barman.conf \ 
	&& echo "" >> /etc/barman.conf && echo "; For archive logs retention" >> /etc/barman.conf && echo "wal_retention_policy = main" >> /etc/barman.conf \ 
	&& echo "" >> /etc/barman.conf && echo "; For automatic retention policies enforcement by the barman cron" >> /etc/barman.conf && echo "retention_policy_mode = auto" >> /etc/barman.conf \ 
	&& echo "" >> /etc/barman.conf && echo "; Incremental backup - Hard links" >> /etc/barman.conf && echo "reuse_backup = link" >> /etc/barman.conf \
	# Cloud hooks - sync WALs and backups to S3
	&& echo "pre_archive_retry_script = '/usr/bin/barman-cloud-wal-archive --cloud-provider aws-s3 --endpoint-url https://${R2_ACCOUNT_ID}.r2.cloudflarestorage.com --aws-profile default s3://${R2_BUCKET}/wal-archives postgres-source-db \\${WAL_FILE}'" >> /etc/barman.conf \
	&& echo "post_backup_retry_script = '/usr/bin/barman-cloud-backup --cloud-provider aws-s3 --endpoint-url https://${R2_ACCOUNT_ID}.r2.cloudflarestorage.com s3://${R2_BUCKET}/base-backups postgres-source-db'" >> /etc/barman.conf

	# Barman Server Setup: per-server configuration via rsync
	RUN mkdir -p /etc/barman.d \
	&& echo "[postgres-source-db]" > /etc/barman.d/postgres-source-db.conf \
	&& echo "description = \"Primary PostgreSQL on Railway\"" >> /etc/barman.d/postgres-source-db.conf \
	&& echo "incoming_wals_directory = /backup/barman/postgres-source-db/incoming" >> /etc/barman.d/postgres-source-db.conf \
	&& echo "streaming_archiver = off" >> /etc/barman.d/postgres-source-db.conf \
	&& echo "archiver = on" >> /etc/barman.d/postgres-source-db.conf \
	&& echo "" >> /etc/barman.d/postgres-source-db.conf \
	# Retention policies
	&& echo "retention_policy_mode = auto" >> /etc/barman.d/postgres-source-db.conf \
	&& echo "retention_policy     = RECOVERY WINDOW OF 7 days" >> /etc/barman.d/postgres-source-db.conf \
	&& echo "wal_retention_policy = main" >> /etc/barman.d/postgres-source-db.conf \
	&& chown barman:barman /etc/barman.d/postgres-source-db.conf \
	&& chmod 600 /etc/barman.d/postgres-source-db.conf

# Set up barman user .ssh directory with proper permissions
RUN su barman -c "mkdir -p /var/lib/barman/.ssh && chmod 700 /var/lib/barman/.ssh && touch /var/lib/barman/.ssh/authorized_keys && chmod 600 /var/lib/barman/.ssh/authorized_keys && touch /var/lib/barman/.pgpass && chmod 0600 /var/lib/barman/.pgpass && echo \"postgres-source-db:*:*:barman:passw0rd\" > /var/lib/barman/.pgpass"

# Custom entrypoint
COPY ./barman/docker-entrypoint.sh /
RUN chmod +x /docker-entrypoint.sh

EXPOSE 22

WORKDIR /var/lib/barman

ENTRYPOINT ["/docker-entrypoint.sh"]
CMD ["barman"]