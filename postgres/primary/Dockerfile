FROM postgres:17.6

ENV POSTGRES_USER="postgres"
ENV POSTGRES_DB="postgres"
ENV POSTGRES_PASSWORD="postgres"

ENV POSTGRES_INITDB_ARGS="--data-checksums"
ENV POSTGRES_HOST_AUTH_METHOD=md5
ENV PGDATA=/var/lib/postgresql/data/pgdata

RUN apt-get update \
 && apt-get install -y openssh-server rsync \
 && rm -rf /var/lib/apt/lists/* \
 && mkdir -p /var/run/sshd

RUN echo "export VISIBLE=now"     >> /etc/profile \
 && echo "export POSTGRES_USER=${POSTGRES_USER}"   >> /etc/profile \
 && echo "export POSTGRES_DB=${POSTGRES_DB}"       >> /etc/profile \
 && echo "export POSTGRES_PASSWORD=${POSTGRES_PASSWORD}" >> /etc/profile

RUN mkdir -p /root/.ssh \
 && chmod 700 /root/.ssh \
 && touch /root/.ssh/authorized_keys \
 && chmod 600 /root/.ssh/authorized_keys \
 && su - postgres -c "mkdir -p ~/.ssh && chmod 700 ~/.ssh && touch ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"

RUN mkdir -p /var/lib/postgresql/config \
 && chown postgres:postgres /var/lib/postgresql/config
COPY ./postgres/common/pg_hba.conf /var/lib/postgresql/config/pg_hba.conf

COPY ./postgres/common/01-init-custom-config.sh /docker-entrypoint-initdb.d/01-init-custom-config.sh
COPY ./postgres/common/02-db-config.sh        /docker-entrypoint-initdb.d/02-db-config.sh
COPY ./postgres/common/03-init-ssl.sh          /docker-entrypoint-initdb.d/03-init-ssl.sh

RUN chmod +x /docker-entrypoint-initdb.d/0*-init-*.sh

COPY ./postgres/common/wrapper.sh               /usr/local/bin/wrapper.sh
COPY ./postgres/primary/custom-docker-entrypoint.sh /custom-docker-entrypoint.sh
RUN chmod +x /usr/local/bin/wrapper.sh /custom-docker-entrypoint.sh

EXPOSE 22 5432

ENTRYPOINT ["/custom-docker-entrypoint.sh"]
CMD ["postgres"]
