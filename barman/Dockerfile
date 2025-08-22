FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends wget gnupg2 cron openssh-server openssh-client && rm -rf /var/lib/apt/lists/*
RUN sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt/ bookworm-pgdg main" > /etc/apt/sources.list.d/pgdg.list' \
	&& (wget --no-check-certificate --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add - || wget --no-check-certificate --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor > /etc/apt/trusted.gpg.d/apt.postgresql.org.gpg) \
	&& apt-get update && apt-get install -y barman barman-cli-cloud \
	&& rm -rf /var/lib/apt/lists/*

RUN mkdir -p /var/run/sshd
# Don't set a password for root - use key authentication only
RUN sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config

# SSH login fix. Otherwise user is kicked off after login
RUN sed 's@session\s*required\s*pam_loginuid.so@session optional pam_loginuid.so@g' -i /etc/pam.d/sshd
ENV NOTVISIBLE "in users profile"
RUN echo "export VISIBLE=now" >> /etc/profile

RUN mkdir -p /var/lib/barman && chown barman:barman /var/lib/barman \
	&& mkdir -p /var/lib/barman/.ssh && chmod 700 /var/lib/barman/.ssh \
	&& mkdir -p /etc/barman.d \
	&& chown -R barman: /etc/barman.conf \
	&& echo "" >> /etc/cron.d/barman \
	&& echo "0 * * * * barman /usr/bin/barman backup pg-primary-db" > /etc/cron.d/barmanpgbackup && echo "" >> /etc/cron.d/barmanpgbackup \
	&& printf "SHELL=/bin/bash\nPATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin\n* * * * * barman /usr/bin/barman cron >> /var/log/barman/cron.log 2>&1\n" > /etc/cron.d/barman-cron \
	&& chmod 0644 /etc/cron.d/barman-cron \
	&& touch /etc/crontab /etc/cron.*/* \
	&& sed -i.bak 's_^.*compression = gzip_compression = gzip_' /etc/barman.conf \
	&& sed -i.bak 's-^.*immediate_checkpoint = false-immediate_checkpoint = true-' /etc/barman.conf \
	&& sed -i.bak 's-^.*basebackup_retry_times = 0-basebackup_retry_times = 3-' /etc/barman.conf \
	&& sed -i.bak 's-^.*basebackup_retry_sleep = 30-basebackup_retry_sleep = 30-' /etc/barman.conf \
	&& sed -i.bak 's-^.*last_backup_maximum_age =-last_backup_maximum_age = 1 DAYS-' /etc/barman.conf \
	&& sed -i.bak 's-^.*minimum_redundancy = 1-minimum_redundancy = 1-' /etc/barman.conf \
	&& sed -i.bak 's-^.*retention_policy =$-retention_policy = RECOVERY WINDOW OF 1 WEEKS-' /etc/barman.conf \
	&& sed -i.bak 's-^.*log_level = INFO$-log_level = DEBUG-' /etc/barman.conf \
	&& echo "" >> /etc/barman.conf && echo "; For archive logs retention" >> /etc/barman.conf && echo "wal_retention_policy = main" >> /etc/barman.conf \
	&& echo "" >> /etc/barman.conf && echo "; For automatic retention policies enforcement by the barman cron" >> /etc/barman.conf && echo "retention_policy_mode = auto" >> /etc/barman.conf

COPY ./barman/docker-entrypoint.sh /
RUN chmod +x /docker-entrypoint.sh

EXPOSE 22

WORKDIR /var/lib/barman

ENTRYPOINT ["/docker-entrypoint.sh"]
CMD ["barman"]