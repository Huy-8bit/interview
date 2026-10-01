#!/usr/bin/env bash
# Lab 13 — time based retention on retention-demo (retention.ms=60s, segment.ms=10s, segment.bytes=1MB).
# Retention deletes WHOLE closed segments whose newest record is older than retention.ms.
source "$(dirname "$0")/../lib.sh"
T=retention-demo
leader="$(kcli topics -topic $T | awk '$1=="retention-demo"{print $3}')"
files() { docker compose exec -T "$leader" sh -c "ls -l /var/lib/kafka/data/$T-0/" | awk '{print $5, $9}' | grep -E 'log|index|deleted' | column -t; }
offs() { echo "earliest=$(kt kafka-get-offsets --bootstrap-server "$BOOTSTRAP_INTERNAL" --topic $T --time -2 | cut -d: -f3) latest=$(kt kafka-get-offsets --bootstrap-server "$BOOTSTRAP_INTERNAL" --topic $T --time -1 | cut -d: -f3)"; }

banner "0. Topic config (lab-only, never on business topics)"
kt kafka-configs --bootstrap-server "$BOOTSTRAP_INTERNAL" --describe --entity-type topics --entity-name $T 2>/dev/null | grep -oE "(retention.ms|segment.ms|segment.bytes|cleanup.policy|file.delete.delay.ms)=[0-9a-z]+" | sort -u
echo "leader of $T-0: $leader"; offs

L0="$(kt kafka-get-offsets --bootstrap-server "$BOOTSTRAP_INTERNAL" --topic $T --time -1 | cut -d: -f3)"
echo "this run's first offset = $L0"

banner "1. Write 3 batches 12s apart (segment.ms=10s => each batch rolls a new segment)"
for b in 1 2 3; do
  kcli produce -topic $T -count 1500 -value "batch-$b-record-{i}-$(head -c 300 /dev/zero | tr '\0' x)" -async -quiet | tail -1
  sleep 12
done
kcli produce -topic $T -value "roll" -quiet | tail -1
files; offs

banner "2. Wait: retention.ms=60s after a segment's newest record + check every 10s"
for i in $(seq 1 30); do
  sleep 5
  e="$(kt kafka-get-offsets --bootstrap-server "$BOOTSTRAP_INTERNAL" --topic $T --time -2 | cut -d: -f3)"
  echo "+$((i*5))s earliest offset = $e"
  [[ "$e" -gt "$L0" ]] && break
done
files; offs
expect "segment of batch 1 deleted: log start offset moved past $L0 (now $e)" test "$e" -gt "$L0"
logs_since "$(date -u -v-3M +%Y-%m-%dT%H:%M:%SZ)" "$leader" | grep -iE "retention|Deleting segment|scheduling" | grep "$T" | tail -3 | cut -c1-220

banner "3. A consumer starting 'from the beginning' now starts at the new log start offset"
kcli consume -topic $T -from start -max 1 -max-value 40
lab_done
