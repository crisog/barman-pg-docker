# postgres/standby/Dockerfile
FROM postgres:16

ENV PGDATA=/var/lib/postgresql/data \
    DEBIAN_FRONTEND=noninteractive

# 1) Install only what we need for recover + SSH
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      barman \
      openssh-client \
      rsync \
 && rm -rf /var/lib/apt/lists/*

# 2) Bring in your client auth and wrapper
COPY ./postgres/common/pg_hba.conf   /var/lib/postgresql/config/pg_hba.conf
COPY ./postgres/common/wrapper.sh    /usr/local/bin/wrapper.sh

# 3) Copy in our custom entrypoint
COPY ./postgres/standby/custom-docker-entrypoint.sh /usr/local/bin/custom-docker-entrypoint.sh

# 4) Make them executable
RUN chmod +x /usr/local/bin/wrapper.sh \
             /usr/local/bin/custom-docker-entrypoint.sh

# 5) Expose Postgres port & launch
EXPOSE 5432
ENTRYPOINT ["/usr/local/bin/custom-docker-entrypoint.sh"]
CMD ["postgres"]
