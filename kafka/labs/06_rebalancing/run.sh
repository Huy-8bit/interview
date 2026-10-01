#!/usr/bin/env bash
# Lab 06 — rebalancing: graceful leave vs crash (session timeout), eager vs cooperative vs KIP-848.
#   ./labs/06_rebalancing/run.sh            all parts
#   PARTS="A B" ./labs/06_rebalancing/run.sh
source "$(dirname "$0")/../lib.sh"
PARTS="${PARTS:-A B C D E}"
OC="order-consumer-1 order-consumer-2 order-consumer-3"
ms() { python3 -c 'import time; print(int(time.time()*1000))'; }
hms() { python3 -c 'import datetime,sys; print(datetime.datetime.fromtimestamp(int(sys.argv[1])/1000, datetime.timezone.utc).strftime("%H:%M:%S.%f")[:-3])' "$1"; }
# milliseconds between an epoch-ms and the time= of the first log line matching pattern (log time is local HH:MM:SS.mmm)
first_log_ms() { # first_log_ms <since> <pattern> <services...>
  local since="$1" pat="$2"; shift 2
  logs_since "$since" "$@" | grep -E "$pat" | head -1 | sed -n 's/^time=\([0-9:.]*\).*/\1/p'
}
delta_ms() { python3 - "$1" "$2" <<'PY'
import sys, datetime
t0 = int(sys.argv[1]); hhmmss = sys.argv[2]
d = datetime.datetime.fromtimestamp(t0/1000, datetime.timezone.utc)  # container logs are UTC
h, m, s = hhmmss.split(":"); sec, msec = s.split(".")
t = d.replace(hour=int(h), minute=int(m), second=int(sec), microsecond=int(msec)*1000)
print(int((t - d).total_seconds()*1000))
PY
}
recreate_consumers() { # recreate_consumers <balancer> <protocol>
  ORDER_BALANCER="$1" ORDER_GROUP_PROTOCOL="$2" docker compose up -d $OC 2>&1 | grep -c Started >/dev/null || true
  kcli group -group order-processing-group -wait-members 3 -timeout 120s | head -5
}

curl -s -X POST "localhost:8001/start?mode=constant&rate=50&duration=0s" >/dev/null && echo "traffic: 50 msg/s"
kcli group -group order-processing-group -wait-members 3 -timeout 60s | head -5

if [[ " $PARTS " == *" A "* ]]; then
banner "A. Graceful stop of order-consumer-2 (SIGTERM -> commit -> LeaveGroup)"
T0="$(now_ts)"; t0="$(ms)"; echo "stop at $(hms "$t0") UTC"
docker compose stop order-consumer-2 >/dev/null 2>&1
sleep 6
logs_since "$T0" order-consumer-2 | grep -E "shutdown|revoked" | grep -E "group=order-processing-group( |$)" | cut -c1-200
logs_since "$T0" order-consumer-1 order-consumer-3 | grep -E "REBALANCE" | grep "group=order-processing-group " | cut -c1-200
t="$(first_log_ms "$T0" "assigned.*group=order-processing-group .*newly_assigned=orders" order-consumer-1 order-consumer-3)"
[[ -n "$t" ]] && echo ">>> orphaned partitions re-assigned $(delta_ms "$t0" "$t") ms after docker stop"
expect "survivors received the partitions of order-consumer-2" test -n "$t"
kcli group -group order-processing-group | head -5

banner "A2. Start order-consumer-2 again -> another rebalance (cooperative: only moved partitions are revoked)"
T1="$(now_ts)"; t1="$(ms)"
docker compose start order-consumer-2 >/dev/null 2>&1
kcli group -group order-processing-group -wait-members 3 -timeout 60s | head -5
sleep 2
logs_since "$T1" $OC | grep REBALANCE | grep "group=order-processing-group " | cut -c1-200
fi

if [[ " $PARTS " == *" B "* ]]; then
banner "B. CRASH order-consumer-2 (SIGKILL: no LeaveGroup). Group notices only after session.timeout.ms=10s"
kcli group -group order-processing-group -wait-members 3 -timeout 60s >/dev/null
T0="$(now_ts)"; t0="$(ms)"; echo "kill -9 at $(hms "$t0") UTC"
docker compose kill -s KILL order-consumer-2 >/dev/null 2>&1
sleep 5
echo "--- 5s after the crash: the dead member still OWNS its partitions, their lag grows:"
kcli group -group order-processing-group | sed -n '1,12p'
t="$(wait_log "$T0" 30 "assigned.*group=order-processing-group .*newly_assigned=orders" order-consumer-1 order-consumer-3 | head -1 | sed -n 's/^time=\([0-9:.]*\).*/\1/p')"
[[ -n "$t" ]] && echo ">>> partitions re-assigned $(delta_ms "$t0" "$t") ms after the crash (session timeout 10s + rejoin)"
d="$(delta_ms "$t0" "${t:-00:00:00.000}")"
expect "crash detection took >= 8s (session timeout), graceful leave did not" test "$d" -ge 8000
docker compose start order-consumer-2 >/dev/null 2>&1   # restart policy does not restart a 'docker kill'ed container started by compose kill
kcli group -group order-processing-group -wait-members 3 -timeout 60s | head -5
fi

if [[ " $PARTS " == *" C "* ]]; then
banner "C. EAGER protocol (range assignor): every rebalance revokes EVERYTHING from everyone"
recreate_consumers range classic
T0="$(now_ts)"
docker compose stop order-consumer-2 >/dev/null 2>&1; sleep 5
logs_since "$T0" order-consumer-1 order-consumer-3 | grep REBALANCE | grep "group=order-processing-group " | cut -c1-200
n="$(logs_since "$T0" order-consumer-1 order-consumer-3 | grep 'group=order-processing-group ' | grep -c 'revoked="orders\|revoked=orders' || true)"
expect "eager: survivors revoked their own partitions too ($n revoke events)" test "$n" -ge 2
docker compose start order-consumer-2 >/dev/null 2>&1
kcli group -group order-processing-group -wait-members 3 -timeout 60s | head -5
fi

if [[ " $PARTS " == *" D "* ]]; then
banner "D. COOPERATIVE sticky: same stop, survivors keep what they own"
recreate_consumers cooperative-sticky classic
T0="$(now_ts)"
docker compose stop order-consumer-2 >/dev/null 2>&1; sleep 5
logs_since "$T0" order-consumer-1 order-consumer-3 | grep REBALANCE | grep "group=order-processing-group " | cut -c1-200
n="$(logs_since "$T0" order-consumer-1 order-consumer-3 | grep 'group=order-processing-group ' | grep 'revoked' | grep -vc 'revoked=(none)' || true)"
expect "cooperative: survivors revoked nothing ($n non-empty revokes)" test "$n" = 0
docker compose start order-consumer-2 >/dev/null 2>&1
kcli group -group order-processing-group -wait-members 3 -timeout 60s | head -5
fi

if [[ " $PARTS " == *" E "* ]]; then
banner "E. KIP-848 'consumer' protocol: the broker (group coordinator) computes the assignment"
recreate_consumers range consumer
T0="$(now_ts)"
docker compose stop order-consumer-2 >/dev/null 2>&1; sleep 5
logs_since "$T0" order-consumer-1 order-consumer-3 | grep REBALANCE | grep "group=order-processing-group " | cut -c1-200
kcli group -group order-processing-group | head -6
out="$(kcli group -group order-processing-group | head -1)"
expect "group runs the consumer protocol (KIP-848)" bash -c "echo '$out' | grep -q 'KIP-848'"
docker compose start order-consumer-2 >/dev/null 2>&1
sleep 8
kcli group -group order-processing-group | head -6
banner "restore default: cooperative-sticky + classic"
recreate_consumers cooperative-sticky classic
fi

curl -s -X POST "localhost:8001/start?mode=constant&rate=5&duration=0s" >/dev/null
lab_done
