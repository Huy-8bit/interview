#!/usr/bin/env bash
# =============================================================================
# Replica entrypoint
#
# First start (empty volume):
#   1. wait until the primary accepts connections
#   2. pg_basebackup: copy the primary's data directory over a replication
#      connection, streaming the WAL generated meanwhile (--wal-method=stream)
#   3. --write-recovery-conf: create standby.signal and put primary_conninfo /
#      primary_slot_name into postgresql.auto.conf
#   4. start postgres -> it sees standby.signal, enters recovery (hot standby),
#      and its walreceiver connects to the primary's walsender
#
# Later starts: the data directory exists -> just start postgres; it resumes
# streaming from the last replayed LSN (the slot kept the needed WAL).
# =============================================================================
set -Eeuo pipefail

: "${PGDATA:=/var/lib/postgresql/data/pgdata}"
: "${PRIMARY_HOST:=postgres-primary}"
: "${PRIMARY_PORT:=5432}"
: "${REPLICATION_USER:=replicator}"
: "${REPLICATION_PASSWORD:?REPLICATION_PASSWORD must be set}"
: "${REPLICATION_SLOT:=replica_1_slot}"

VOLUME_ROOT="$(dirname "$PGDATA")"
BOOTSTRAP_MARKER="$VOLUME_ROOT/.bootstrap-complete"

log() { echo "[replica-entrypoint] $(date -u '+%Y-%m-%d %H:%M:%S') UTC  $*"; }

# ---- Step 0: running as root -> fix ownership, then re-exec as postgres -------
if [ "$(id -u)" = '0' ]; then
  mkdir -p "$PGDATA" /var/run/postgresql
  chown -R postgres:postgres "$VOLUME_ROOT" /var/run/postgresql
  chmod 0700 "$PGDATA"
  exec gosu postgres "${BASH_SOURCE[0]}" "$@"
fi

# ---- Step 1: bootstrap from the primary if needed -------------------------------
if [ ! -f "$BOOTSTRAP_MARKER" ]; then
  log "no completed base backup found -> bootstrapping replica from ${PRIMARY_HOST}:${PRIMARY_PORT}"

  until pg_isready -h "$PRIMARY_HOST" -p "$PRIMARY_PORT" -q; do
    log "waiting for primary to accept connections..."
    sleep 2
  done

  # pg_basebackup requires an empty target directory; also clears a
  # half-finished backup from an interrupted previous attempt.
  find "$PGDATA" -mindepth 1 -delete

  log "running pg_basebackup (slot=${REPLICATION_SLOT})"
  PGPASSWORD="$REPLICATION_PASSWORD" pg_basebackup \
    --host="$PRIMARY_HOST" \
    --port="$PRIMARY_PORT" \
    --username="$REPLICATION_USER" \
    --pgdata="$PGDATA" \
    --format=plain \
    --wal-method=stream \
    --slot="$REPLICATION_SLOT" \
    --write-recovery-conf \
    --checkpoint=fast \
    --progress \
    --verbose

  chmod 0700 "$PGDATA"
  touch "$BOOTSTRAP_MARKER"
  log "base backup complete; standby.signal + primary_conninfo written to postgresql.auto.conf"
else
  log "existing data directory found -> starting (resume streaming)"
fi

if [ ! -f "$PGDATA/standby.signal" ]; then
  log "WARNING: standby.signal is missing -> this node was PROMOTED and will start as a read-write primary."
  log "         Rebuild it as a replica with: ./scripts/rebuild-replica.sh"
fi

exec "$@"
