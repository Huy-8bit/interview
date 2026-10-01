ARG PG_MAJOR=16
FROM postgres:${PG_MAJOR}-bookworm

# procps: `ps` to look at the PostgreSQL process model (walsender, walreceiver, startup...)
RUN apt-get update \
 && apt-get install -y --no-install-recommends procps \
 && rm -rf /var/lib/apt/lists/*

COPY postgresql.conf /etc/postgresql/postgresql.conf
COPY pg_hba.conf     /etc/postgresql/pg_hba.conf
COPY entrypoint.sh   /usr/local/bin/replica-entrypoint.sh
RUN chmod 0755 /usr/local/bin/replica-entrypoint.sh

# The volume is mounted at /var/lib/postgresql/data; the cluster lives in a
# sub-directory so the entrypoint can keep a "bootstrap complete" marker next
# to it (and wipe/retry a half-finished pg_basebackup safely).
ENV PGDATA=/var/lib/postgresql/data/pgdata

# The official image's entrypoint (initdb + init scripts) is replaced:
# a replica's data directory must be a byte-for-byte copy of the primary.
ENTRYPOINT ["replica-entrypoint.sh"]
CMD ["postgres", "-c", "config_file=/etc/postgresql/postgresql.conf"]
