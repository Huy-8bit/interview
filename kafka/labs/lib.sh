#!/usr/bin/env bash
# Helpers for labs/*/run.sh (sources scripts/lib.sh: kt, kcli, banner, ok, fail ...)
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/lib.sh"
# labs pipe into head/grep a lot: a closed pipe (SIGPIPE) must not abort the lab
set +o pipefail

LAB_FAILS=0
expect() { # expect "<description>" <command...>   -> records PASS/FAIL, never aborts the lab
  local d="$1"; shift
  if "$@" >/dev/null 2>&1; then ok "EXPECT: $d"; else fail "EXPECT: $d"; LAB_FAILS=$((LAB_FAILS+1)); fi
}
lab_done() {
  echo
  if (( LAB_FAILS == 0 )); then ok "LAB PASSED"; else fail "LAB: $LAB_FAILS expectation(s) failed"; exit 1; fi
}
# logs of a compose service since a timestamp (docker --since accepts RFC3339)
logs_since() { docker compose logs --no-log-prefix --since "$1" "${@:2}" 2>/dev/null; }
now_ts() { date -u +%Y-%m-%dT%H:%M:%SZ; }
order_consumer_logs() { logs_since "$1" order-consumer-1 order-consumer-2 order-consumer-3; }
# wait_log <since> <timeout_s> <grep -E pattern> <services...> : waits until a log line matches, prints it
wait_log() {
  local since="$1" t="$2" pat="$3"; shift 3
  local i=0 out=""
  while (( i < t )); do
    out="$(logs_since "$since" "$@" | grep -E "$pat" || true)"
    [[ -n "$out" ]] && { echo "$out"; return 0; }
    sleep 1; i=$((i+1))
  done
  return 1
}
