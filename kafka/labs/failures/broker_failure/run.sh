#!/usr/bin/env bash
# Planned broker shutdown (SIGTERM -> controlled shutdown) under load: leaders are moved
# BEFORE the broker stops, so producers see (almost) nothing. Compare with leader_failure (kill -9).
source "$(dirname "$0")/../../lib.sh"
end_total() { kt kafka-get-offsets --bootstrap-server "$BOOTSTRAP_INTERNAL" --topic orders --time -1 2>/dev/null | awk -F: '{s+=$3} END{print s}'; }
curl -s -X POST localhost:8001/stop >/dev/null; sleep 2
before="$(end_total)"
curl -s -X POST "localhost:8001/start?mode=constant&rate=200&duration=40s" >/dev/null
sleep 8
banner "graceful stop of kafka-2 (docker stop = SIGTERM)"
T0="$(now_ts)"
docker compose stop kafka-2 >/dev/null 2>&1
logs_since "$T0" kafka-2 | grep -iE "controlled shutdown|ControlledShutdown|shutting down" | head -4 | cut -c1-200
kcli topics -topic orders | tail -9
sleep 5
docker compose start kafka-2 >/dev/null 2>&1
for i in $(seq 1 30); do st="$(curl -s localhost:8001/status)"; echo "$st" | grep -q '"running": false' && break; sleep 3; done
after="$(end_total)"
read -r acked failed < <(echo "$st" | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d["sent"], d["failed"])')
echo "acked=$acked failed=$failed appended=$((after-before))"
expect "no producer failure during a controlled shutdown" test "$failed" = 0
expect "every acked record is in the log" test "$((after-before))" = "$acked"
wait_healthy kafka-2 180; wait_isr_full 240 && ok "kafka-2 back in sync"
curl -s -X POST "localhost:8001/start?mode=constant&rate=5&duration=0s" >/dev/null
lab_done
