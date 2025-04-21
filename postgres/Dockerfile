# Postgres
FROM postgres:16
ENV POSTGRES_USER dbadmin	 
ENV POSTGRES_DB db
ENV POSTGRES_PASSWORD passw0rd
# Point PostgreSQL to a subdirectory of the mounted volume
ENV PGDATA /var/lib/postgresql/data/pgdata
# Add necessary PostgreSQL configuration
ENV POSTGRES_INITDB_ARGS "--data-checksums"
ENV POSTGRES_HOST_AUTH_METHOD "md5"

# SSH Setup
RUN apt-get update && apt-get install -y openssh-server rsync && rm -rf /var/lib/apt/lists/*
RUN mkdir -p /var/run/sshd
RUN echo 'root:password' | chpasswd
RUN sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config
RUN echo "Host *barman*" >> /etc/ssh/ssh_config && echo " StrictHostKeyChecking no" >> /etc/ssh/ssh_config

# SSH login fix. Otherwise user is kicked off after login
RUN sed 's@session\s*required\s*pam_loginuid.so@session optional pam_loginuid.so@g' -i /etc/pam.d/sshd
ENV NOTVISIBLE "in users profile"
RUN echo "export VISIBLE=now" >> /etc/profile
RUN echo "export POSTGRES_USER=dbadmin" >> /etc/profile
RUN echo "export POSTGRES_DB=db" >> /etc/profile
RUN echo "export POSTGRES_PASSWORD=passw0rd" >> /etc/profile

# Ensure SSH directories exist but don't rely on pre-existing keys
RUN mkdir -p ~/.ssh && chmod 700 ~/.ssh && touch ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys
RUN su - postgres -c "mkdir -p ~postgres/.ssh && chmod 700 ~postgres/.ssh && touch ~postgres/.ssh/authorized_keys && chmod 600 ~postgres/.ssh/authorized_keys"

# Custom config
RUN mkdir -p /var/lib/postgresql/config/
COPY ./postgres/pg_hba.conf /var/lib/postgresql/config/
RUN chown -R postgres: /var/lib/postgresql/config/

# Create a custom PostgreSQL config file
RUN echo "wal_level = hot_standby" > /tmp/postgresql.conf && \
    echo "archive_mode = on" >> /tmp/postgresql.conf && \
    echo "archive_command = 'rsync -a %p barman@barman-pg-docker-6ed36822.railway.internal:/backup/barman/postgres-source-db/incoming/%f || exit 0'" >> /tmp/postgresql.conf && \
    echo "max_wal_senders = 2" >> /tmp/postgresql.conf && \
    echo "max_replication_slots = 2" >> /tmp/postgresql.conf && \
    echo "hba_file = '/var/lib/postgresql/config/pg_hba.conf'" >> /tmp/postgresql.conf && \
    mkdir -p /etc/postgresql && \
    cp /tmp/postgresql.conf /etc/postgresql/postgresql.conf && \
    chown postgres:postgres /etc/postgresql/postgresql.conf

COPY ./postgres/db-config.sh /docker-entrypoint-initdb.d/

# Custom entrypoint
COPY ./postgres/docker-entrypoint.sh /
RUN chmod +x /docker-entrypoint.sh

EXPOSE 22 5432

ENTRYPOINT ["/docker-entrypoint.sh"]
CMD ["postgres", "-c", "config_file=/etc/postgresql/postgresql.conf"]