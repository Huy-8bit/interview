#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Runs once on first start of the primary (empty data directory).
# Creates the dedicated replication role and the physical replication slot the
# replica streams from. Written as .sh (not .sql) so the password comes from
# the environment instead of being hard-coded.
# -----------------------------------------------------------------------------
set -euo pipefail

: "${REPLICATION_USER:=replicator}"
: "${REPLICATION_PASSWORD:?REPLICATION_PASSWORD must be set}"
: "${REPLICATION_SLOT:=replica_1_slot}"

echo "[init] creating replication role '${REPLICATION_USER}' and slot '${REPLICATION_SLOT}'"

psql -v ON_ERROR_STOP=1 --no-psqlrc \
     --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" \
     --set repl_user="$REPLICATION_USER" \
     --set repl_password="$REPLICATION_PASSWORD" \
     --set repl_slot="$REPLICATION_SLOT" <<'EOSQL'
-- REPLICATION: may open replication connections (walsender / pg_basebackup).
-- It is NOT a superuser and cannot read table data through normal SQL.
CREATE ROLE :"repl_user" WITH LOGIN REPLICATION PASSWORD :'repl_password';
COMMENT ON ROLE :"repl_user" IS 'Streaming replication / pg_basebackup only';

-- A physical slot makes the primary keep every WAL segment the replica has not
-- confirmed yet, so a replica that was down can always catch up
-- (bounded by max_slot_wal_keep_size).
SELECT slot_name, lsn
FROM pg_create_physical_replication_slot(:'repl_slot', true);
EOSQL
