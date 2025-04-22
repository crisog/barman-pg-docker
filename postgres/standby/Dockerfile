FROM postgres:16

ENV POSTGRES_USER="postgres" \
    POSTGRES_DB="postgres" \
    POSTGRES_PASSWORD="postgres" \
    POSTGRES_INITDB_ARGS="--data-checksums" \
    POSTGRES_HOST_AUTH_METHOD=md5

RUN apt-get update \
 && apt-get install -y --no-install-recommends openssh-server rsync \
 && rm -rf /var/lib/apt/lists/* \
 && mkdir -p /var/run/sshd

COPY ../common/pg_hba.conf   /var/lib/postgresql/config/pg_hba.conf
COPY ../common/wrapper.sh    /usr/local/bin/wrapper.sh

COPY custom-docker-entrypoint.sh /usr/local/bin/custom-docker-entrypoint.sh
RUN chmod +x /usr/local/bin/wrapper.sh \
                /usr/local/bin/custom-docker-entrypoint.sh

EXPOSE 22 5432
ENTRYPOINT ["/usr/local/bin/custom-docker-entrypoint.sh"]
CMD ["postgres"]
