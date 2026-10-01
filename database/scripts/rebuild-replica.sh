#!/usr/bin/env bash
# =============================================================================
# Throw away the replica's data and re-clone it from the primary.
# Use after a failover/promote exercise, or if the replica fell too far behind
# (slot invalidated: wal_status = 'lost').
#   ./scripts/rebuild-replica.sh [-y]
# =============================================================================
. "$(dirname "$0")/lib.sh"

SLOT="${REPLICATION_SLOT:-replica_1_slot}"
VOLUME="postgresql-lab_postgres_replica_data"

if [ "${1:-}" != "-y" ]; then
  read -r -p "This deletes volume $VOLUME and re-clones the replica. Continue? [y/N] " answer
  [[ "$answer" =~ ^[Yy]$ ]] || { echo "aborted"; exit 1; }
fi

require_running "$PRIMARY_SERVICE"

header "Stop and remove replica"
docker compose rm --stop --force "$REPLICA_SERVICE"
docker volume rm "$VOLUME" >/dev/null 2>&1 && ok "volume $VOLUME removed" || warn "volume $VOLUME did not exist"

header "Make sure slot '$SLOT' exists on the primary"
psql_on "$PRIMARY_SERVICE" -c "
SELECT CASE WHEN EXISTS (SELECT 1 FROM pg_replication_slots WHERE slot_name = '$SLOT')
            THEN 'slot exists'
            ELSE (SELECT 'created slot at ' || lsn FROM pg_create_physical_replication_slot('$SLOT', true))
       END AS slot;"

header "Start replica (pg_basebackup runs in its entrypoint)"
docker compose up -d "$REPLICA_SERVICE"
echo "Follow progress:  docker compose logs -f $REPLICA_SERVICE"
echo "Then verify:      ./scripts/check-replication.sh"
