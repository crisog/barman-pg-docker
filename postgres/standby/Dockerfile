FROM postgres:16

ENV PGDATA=/var/lib/postgresql/data \
    DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
 && apt-get install -y openssh-server rsync \
 && rm -rf /var/lib/apt/lists/* \
 && mkdir -p /var/run/sshd

COPY ./postgres/common/pg_hba.conf   /var/lib/postgresql/config/pg_hba.conf
COPY ./postgres/common/wrapper.sh    /usr/local/bin/wrapper.sh

COPY ./postgres/standby/custom-docker-entrypoint.sh /usr/local/bin/custom-docker-entrypoint.sh

RUN chmod +x /usr/local/bin/wrapper.sh \
             /usr/local/bin/custom-docker-entrypoint.sh

EXPOSE 22 5432
ENTRYPOINT ["/usr/local/bin/custom-docker-entrypoint.sh"]
CMD ["postgres"]
