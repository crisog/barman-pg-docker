FROM postgres:16

ENV PGDATA=/var/lib/postgresql/data \
    DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
 && apt-get install -y openssh-server rsync \
 && rm -rf /var/lib/apt/lists/* \
 && mkdir -p /var/run/sshd

COPY ./postgres/common/pg_hba.conf   /var/lib/postgresql/config/pg_hba.conf
COPY ./postgres/common/wrapper.sh    /usr/local/bin/wrapper.sh
COPY ./postgres/common/01-init-custom-config.sh /docker-entrypoint-initdb.d/01-init-custom-config.sh
COPY ./postgres/common/03-init-ssl.sh /docker-entrypoint-initdb.d/03-init-ssl.sh
COPY ./postgres/standby/setup-replication-user.sh /usr/local/bin/setup-replication-user.sh

COPY ./postgres/standby/custom-docker-entrypoint.sh /usr/local/bin/custom-docker-entrypoint.sh

RUN chmod +x /usr/local/bin/wrapper.sh \
             /usr/local/bin/custom-docker-entrypoint.sh \
             /docker-entrypoint-initdb.d/01-init-custom-config.sh \
             /docker-entrypoint-initdb.d/03-init-ssl.sh \
             /usr/local/bin/setup-replication-user.sh

EXPOSE 22 5432
ENTRYPOINT ["/usr/local/bin/custom-docker-entrypoint.sh"]
CMD ["postgres"]
