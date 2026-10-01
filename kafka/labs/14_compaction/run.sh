#!/usr/bin/env bash
# Lab 14 — log compaction on user-profile-compacted: keep the LATEST value per key; tombstones delete keys.
source "$(dirname "$0")/../lib.sh"
T=user-profile-compacted
RUN="$(date +%s)"
U1="user-$RUN-1"; U2="user-$RUN-2"; U3="user-$RUN-3"
show() { kcli consume -topic $T -from start -idle 3s -max-value 60 | grep -E "$RUN|record" ; }

banner "0. Config"
kt kafka-configs --bootstrap-server "$BOOTSTRAP_INTERNAL" --describe --entity-type topics --entity-name $T 2>/dev/null | grep -oE "(cleanup.policy|segment.ms|min.cleanable.dirty.ratio|delete.retention.ms|min.compaction.lag.ms)=[0-9a-z.]+" | sort -u

banner "1. Write history: $U1 v1 v2 v3, $U2 v1, $U3 v1 then TOMBSTONE (null value) for $U3"
for v in 1 2 3; do kcli produce -topic $T -key "$U1" -value "{\"name\":\"An\",\"tier\":\"v$v\"}" | head -1; done
kcli produce -topic $T -key "$U2" -value '{"name":"Binh","tier":"v1"}' | head -1
kcli produce -topic $T -key "$U3" -value '{"name":"Chi","tier":"v1"}' | head -1
kcli produce -topic $T -key "$U3" -null-value | head -1
show

banner "2. Compaction runs only on CLOSED segments: wait segment.ms (15s), then write a filler record to every partition to roll"
sleep 16
for p in 0 1 2; do kcli produce -topic $T -partition $p -key "filler-$RUN-$p" -value filler -quiet | tail -1; done
for i in $(seq 1 24); do
  sleep 5
  n="$(kcli consume -topic $T -from start -idle 3s | grep -c "key=$U1 " || true)"
  echo "+$((i*5))s records with key $U1 still in the log: $n"
  [[ "$n" == 1 ]] && break
done
show
expect "only the latest value of $U1 survives compaction" test "$n" = 1
kcli consume -topic $T -from start -idle 3s | grep "key=$U1 " | grep -q 'v3' && ok "the survivor is v3"

banner "3. Tombstone: kept for delete.retention.ms (20s) so consumers see the delete, then removed by a later clean"
sleep 22
for p in 0 1 2; do kcli produce -topic $T -partition $p -key "filler2-$RUN-$p" -value filler -quiet | tail -1; done
for i in $(seq 1 24); do
  sleep 5
  t="$(kcli consume -topic $T -from start -idle 3s | grep -c "key=$U3 " || true)"
  echo "+$((i*5))s records with key $U3: $t"
  [[ "$t" == 0 ]] && break
done
expect "deleted key $U3 fully gone (value + tombstone)" test "$t" = 0
show
step "offsets are NOT renumbered: compaction leaves gaps"
kcli consume -topic $T -from start -idle 3s | grep -E "$RUN" | awk '{print $2, $3, $4}'
lab_done
