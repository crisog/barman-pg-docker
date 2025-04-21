# PostgreSQL with SSL (Railway base) and custom Barman/SSH setup
FROM ghcr.io/railwayapp-templates/postgres-ssl:16

# Required build-time args; fails if not provided
ARG POSTGRES_USER
ARG POSTGRES_DB
ARG POSTGRES_PASSWORD
ARG PGDATA

# Validate build args
RUN if [ -z "$POSTGRES_USER" ] || [ -z "$POSTGRES_DB" ] || [ -z "$POSTGRES_PASSWORD" ] || [ -z "$PGDATA" ]; then \
      echo "ERROR: Missing required build args POSTGRES_USER, POSTGRES_DB, POSTGRES_PASSWORD, or PGDATA" >&2; \
      exit 1; \
    fi

# Export env vars from build args
ENV POSTGRES_USER=${POSTGRES_USER}
ENV POSTGRES_DB=${POSTGRES_DB}
ENV POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
ENV PGDATA=${PGDATA}

ENV POSTGRES_INITDB_ARGS="--data-checksums"
ENV POSTGRES_HOST_AUTH_METHOD=md5

# SSH and rsync for Barman backups
RUN apt-get update && apt-get install -y openssh-server rsync && rm -rf /var/lib/apt/lists/* \
 && mkdir -p /var/run/sshd \
 && echo 'root:password' | chpasswd \
 && sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config \
 && { echo "Host *barman*"; echo "  StrictHostKeyChecking no"; } >> /etc/ssh/ssh_config \
 && sed 's@session\\s*required\\s*pam_loginuid.so@session optional pam_loginuid.so@g' -i /etc/pam.d/sshd

# Persist SSH env vars
ENV NOTVISIBLE="in users profile"
RUN echo "export VISIBLE=now" >> /etc/profile \
 && echo "export POSTGRES_USER=${POSTGRES_USER}" >> /etc/profile \
 && echo "export POSTGRES_DB=${POSTGRES_DB}" >> /etc/profile \
 && echo "export POSTGRES_PASSWORD=${POSTGRES_PASSWORD}" >> /etc/profile

# Ensure SSH dirs exist
RUN mkdir -p /root/.ssh && chmod 700 /root/.ssh && touch /root/.ssh/authorized_keys && chmod 600 /root/.ssh/authorized_keys \
 && su - postgres -c "mkdir -p ~postgres/.ssh && chmod 700 ~postgres/.ssh && touch ~postgres/.ssh/authorized_keys && chmod 600 ~postgres/.ssh/authorized_keys"

# Copy custom pg_hba.conf into data dir
COPY ./postgres/pg_hba.conf $PGDATA/pg_hba.conf
RUN chown postgres:postgres $PGDATA/pg_hba.conf

# Write custom postgresql.conf into data dir for Railway wrapper
RUN { \
    echo "listen_addresses = '*'"; \
    echo "wal_level = hot_standby"; \
    echo "archive_mode = on"; \
    echo "archive_command = 'rsync -a %p barman@barman-pg-docker-6ed36822.railway.internal:/backup/barman/postgres-source-db/incoming/%f || exit 0'"; \
    echo "max_wal_senders = 2"; \
    echo "max_replication_slots = 2"; \
    echo "hba_file = '$PGDATA/pg_hba.conf'"; \
} > $PGDATA/postgresql.conf \
 && chown postgres:postgres $PGDATA/postgresql.conf

# DB init scripts (roles, permissions)
COPY ./postgres/db-config.sh /docker-entrypoint-initdb.d/
RUN chmod 755 /docker-entrypoint-initdb.d/db-config.sh

# Custom entrypoint (Barman/SSH + Railway SSL wrapper)
COPY ./postgres/docker-entrypoint.sh /docker-entrypoint.sh
RUN chmod +x /docker-entrypoint.sh

# Expose SSH + Postgres ports
EXPOSE 22 5432

ENTRYPOINT ["/docker-entrypoint.sh"]
# No CMD: wrapper.sh (called by entrypoint) will default to `postgres --port=5432`