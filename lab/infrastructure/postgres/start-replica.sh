#!/bin/sh
set -eu
if [ "$(id -u)" = 0 ]; then
  mkdir -p "$PGDATA"
  chown postgres:postgres /var/lib/postgresql/data "$PGDATA"
  chmod 700 "$PGDATA"
  exec su-exec postgres sh "$0"
fi
umask 077
escaped_password=$(printf '%s' "$REPLICATION_PASSWORD" | sed 's/\\/\\\\/g; s/:/\\:/g')
printf 'postgres-primary:5432:*:replicator:%s\n' "$escaped_password" > /var/lib/postgresql/data/replication.pgpass
if [ ! -s "$PGDATA/PG_VERSION" ]; then
  # Never reset an existing database or partially initialized directory silently.
  [ -z "$(ls -A "$PGDATA")" ] || { echo 'Replica PGDATA is nonempty but incomplete' >&2; exit 1; }
  pg_basebackup --dbname="host=postgres-primary port=5432 user=replicator application_name=postgres-replica connect_timeout=5 passfile=/var/lib/postgresql/data/replication.pgpass" \
    --pgdata="$PGDATA" --wal-method=stream --write-recovery-conf \
    --slot=lab_physical_replica --checkpoint=fast
fi
[ -f "$PGDATA/standby.signal" ] || { echo 'Refusing to start a promoted replica as a standby' >&2; exit 1; }
exec postgres -c hot_standby=on -c max_connections=200 \
  -c wal_level=logical -c max_wal_senders=16 -c max_replication_slots=16 \
  -c hba_file=/etc/postgresql/pg_hba.conf
