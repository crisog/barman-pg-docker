# PostgreSQL w/ SSL (Railway) + custom Barman/SSH
FROM ghcr.io/railwayapp-templates/postgres-ssl:16

# Require build args; fail early if missing
ENV POSTGRES_USER="postgres"
ENV POSTGRES_DB="postgres"
ENV POSTGRES_PASSWORD="postgres"
ENV PGDATA="/var/lib/postgresql/data/pgdata"
ENV POSTGRES_INITDB_ARGS="--data-checksums"
ENV POSTGRES_HOST_AUTH_METHOD=md5
ENV POSTGRES_INITDB_ARGS="--data-checksums"
ENV POSTGRES_HOST_AUTH_METHOD=md5

# SSH + rsync for Barman backups
RUN apt-get update \
 && apt-get install -y openssh-server rsync \
 && rm -rf /var/lib/apt/lists/* \
 && mkdir -p /var/run/sshd \
 && echo 'root:password' | chpasswd \
 && sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config \
 && echo "Host *barman*" >> /etc/ssh/ssh_config \
 && echo "  StrictHostKeyChecking no" >> /etc/ssh/ssh_config \
 && sed 's@session\\s*required\\s*pam_loginuid.so@session optional pam_loginuid.so@g' -i /etc/pam.d/sshd

# Persist SSH ENV
ENV NOTVISIBLE="in users profile"
RUN echo "export VISIBLE=now" >> /etc/profile \
 && echo "export POSTGRES_USER=${POSTGRES_USER}" >> /etc/profile \
 && echo "export POSTGRES_DB=${POSTGRES_DB}" >> /etc/profile \
 && echo "export POSTGRES_PASSWORD=${POSTGRES_PASSWORD}" >> /etc/profile

# Prepare SSH dirs
RUN mkdir -p /root/.ssh && chmod 700 /root/.ssh && touch /root/.ssh/authorized_keys && chmod 600 /root/.ssh/authorized_keys \
 && su - postgres -c "mkdir -p ~postgres/.ssh && chmod 700 ~postgres/.ssh && touch ~postgres/.ssh/authorized_keys && chmod 600 ~postgres/.ssh/authorized_keys"

# Copy custom pg_hba into a staging area
RUN mkdir -p /var/lib/postgresql/config/ \
 && chown postgres:postgres /var/lib/postgresql/config/
COPY ./postgres/pg_hba.conf /var/lib/postgresql/config/pg_hba.conf
RUN chown postgres:postgres /var/lib/postgresql/config/pg_hba.conf

# InitDB-time script: writes pg_hba.conf + core config into $PGDATA
COPY ./postgres/01-init-custom-config.sh /docker-entrypoint-initdb.d/01-init-custom-config.sh
RUN chmod +x /docker-entrypoint-initdb.d/01-init-custom-config.sh

# Role/perm seed script (runs during initdb)
COPY ./postgres/02-db-config.sh /docker-entrypoint-initdb.d/02-db-config.sh
RUN chmod +x /docker-entrypoint-initdb.d/02-db-config.sh

# Custom entrypoint (SSH/Barman) then Railway SSL wrapper
COPY ./postgres/custom-docker-entrypoint.sh /custom-docker-entrypoint.sh
RUN chmod +x /custom-docker-entrypoint.sh

EXPOSE 22 5432
ENTRYPOINT ["/custom-docker-entrypoint.sh"]
CMD ["postgres"]