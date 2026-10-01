#!/usr/bin/env bash
# Producer restart: graceful (SIGTERM -> flush buffered records) vs crash (SIGKILL -> buffered,
# un-acked records are gone). A restarted idempotent producer gets a NEW producer id.
source "$(dirname "$0")/../../lib.sh"
pid_of_last_batch() { # producerId of the newest batch in orders P0 on its leader
  local l; l="$(kcli topics -topic orders | awk '$1=="orders" && $2==0 {print $3}')"
  local seg; seg="$(docker compose exec -T "$l" sh -c 'ls /var/lib/kafka/data/orders-0/*.log | tail -1')"
  KT_BROKER="$l" kt kafka-dump-log --files "$seg" 2>/dev/null | grep baseOffset | tail -1 | grep -oE "producerId: [0-9]+"
}
curl -s -X POST "localhost:8001/start?mode=constant&rate=300&duration=0s" >/dev/null; sleep 5
p1="$(pid_of_last_batch)"; echo "traffic-generator before restart: $p1"

banner "1. graceful restart (SIGTERM): the producer flushes what it buffered"
T0="$(now_ts)"
docker compose restart traffic-generator >/dev/null 2>&1
logs_since "$T0" traffic-generator | grep -E "shutdown|finished" | cut -c1-200
expect "graceful shutdown flushed (failed=0)" bash -c "docker compose logs --since $T0 traffic-generator | grep 'shutdown complete' | grep -q 'failed=0'"
wait_healthy traffic-generator 60; sleep 5
p2="$(pid_of_last_batch)"; echo "after restart: $p2"
expect "a restarted idempotent producer gets a new producer id ($p1 -> $p2)" test "$p1" != "$p2"

banner "2. crash (SIGKILL): no flush, no 'shutdown complete' log"
curl -s -X POST "localhost:8001/start?mode=constant&rate=300&duration=0s" >/dev/null; sleep 3
T1="$(now_ts)"
docker compose kill -s KILL traffic-generator >/dev/null 2>&1
n="$(logs_since "$T1" traffic-generator | grep -c 'shutdown complete' || true)"
expect "SIGKILL: the process never reached its shutdown code ($n)" test "$n" = 0
echo "Records accepted by Produce() but not yet acked were lost. The application's source of truth must"
echo "be able to re-send (outbox table / re-read input). Idempotence does NOT survive a restart (new PID)."
docker compose start traffic-generator >/dev/null 2>&1; wait_healthy traffic-generator 60
curl -s -X POST "localhost:8001/start?mode=constant&rate=5&duration=0s" >/dev/null
lab_done
