ARG PG_MAJOR=16
FROM postgres:${PG_MAJOR}-bookworm

# procps: `ps` to look at the PostgreSQL process model (walsender, walreceiver, startup...)
RUN apt-get update \
 && apt-get install -y --no-install-recommends procps \
 && rm -rf /var/lib/apt/lists/*

# Configuration lives outside PGDATA so it is versioned with the project and
# survives `docker compose down -v` / re-initialisation.
COPY postgresql.conf /etc/postgresql/postgresql.conf
COPY pg_hba.conf     /etc/postgresql/pg_hba.conf

# Executed once, in alphabetical order, only when the data directory is empty.
COPY init/ /docker-entrypoint-initdb.d/
RUN chmod 0755 /docker-entrypoint-initdb.d/*.sh

CMD ["postgres", "-c", "config_file=/etc/postgresql/postgresql.conf"]
