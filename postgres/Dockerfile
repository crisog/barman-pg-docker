# Use the official Postgres 16 image
FROM postgres:16

# ---------------------------------------------------------------------------
# 1. Environment
# ---------------------------------------------------------------------------
ENV POSTGRES_USER="postgres"
ENV POSTGRES_DB="postgres"
ENV POSTGRES_PASSWORD="postgres"

# Optional: keep data checksums and enforce md5 auth
ENV POSTGRES_INITDB_ARGS="--data-checksums"
ENV POSTGRES_HOST_AUTH_METHOD=md5

# ---------------------------------------------------------------------------
# 2. Install SSH & rsync for Barman backups
# ---------------------------------------------------------------------------
RUN apt-get update \
 && apt-get install -y openssh-server rsync \
 && rm -rf /var/lib/apt/lists/* \
 # Prepare sshd runtime dir
 && mkdir -p /var/run/sshd

# ---------------------------------------------------------------------------
# 3. Persist SSH env for interactive shells (Railway quirk)
# ---------------------------------------------------------------------------
RUN echo "export VISIBLE=now"     >> /etc/profile \
 && echo "export POSTGRES_USER=${POSTGRES_USER}"   >> /etc/profile \
 && echo "export POSTGRES_DB=${POSTGRES_DB}"       >> /etc/profile \
 && echo "export POSTGRES_PASSWORD=${POSTGRES_PASSWORD}" >> /etc/profile

# ---------------------------------------------------------------------------
# 4. Prepare SSH directories for root & postgres user
# ---------------------------------------------------------------------------
RUN mkdir -p /root/.ssh \
 && chmod 700 /root/.ssh \
 && touch /root/.ssh/authorized_keys \
 && chmod 600 /root/.ssh/authorized_keys \
 && su - postgres -c "mkdir -p ~/.ssh && chmod 700 ~/.ssh && touch ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"

# ---------------------------------------------------------------------------
# 5. Copy your custom config & init‑scripts
# ---------------------------------------------------------------------------
# a) custom pg_hba staging
RUN mkdir -p /var/lib/postgresql/config \
 && chown postgres:postgres /var/lib/postgresql/config
COPY ./postgres/pg_hba.conf /var/lib/postgresql/config/pg_hba.conf

# b) init‑scripts (will run during initdb)
COPY ./postgres/01-init-custom-config.sh /docker-entrypoint-initdb.d/01-init-custom-config.sh
COPY ./postgres/02-db-config.sh        /docker-entrypoint-initdb.d/02-db-config.sh
COPY ./postgres/03-init-ssl.sh          /docker-entrypoint-initdb.d/03-init-ssl.sh

RUN chmod +x /docker-entrypoint-initdb.d/0*-init-*.sh

# c) wrapper + custom entrypoint
COPY ./postgres/wrapper.sh               /usr/local/bin/wrapper.sh
COPY ./postgres/custom-docker-entrypoint.sh /custom-docker-entrypoint.sh
RUN chmod +x /usr/local/bin/wrapper.sh /custom-docker-entrypoint.sh

# ---------------------------------------------------------------------------
# 6. Expose and launch
# ---------------------------------------------------------------------------
EXPOSE 22 5432

ENTRYPOINT ["/custom-docker-entrypoint.sh"]
CMD ["postgres"]
