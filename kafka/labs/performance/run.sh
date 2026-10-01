#!/usr/bin/env bash
# Performance lab — same machine, same workload, one knob at a time.
#   A  partitions 1 / 3 / 6 / 12   -> producer throughput + max consumer parallelism
#   B  acks 0 / 1 / all
#   C  batching: linger 0 + 16KB batches vs linger 20ms + 1MB batches
#   D  compression none / gzip / snappy / lz4 / zstd (JSON payload, compressible)
#   E  consumers 1 / 2 / 3 / 6 / 8 on a 6-partition topic (1ms work per record)
# Numbers depend on your laptop and Docker VM; compare RELATIVE differences.
#   RECORDS=100000 ./labs/performance/run.sh      PARTS="A B" ./labs/performance/run.sh
source "$(dirname "$0")/../lib.sh"
N="${RECORDS:-100000}"; PARTS="${PARTS:-A B C D E}"
OUT="$(dirname "$0")/last-run.txt"
exec > >(tee "$OUT") 2>&1

curl -s -X POST localhost:8001/stop >/dev/null
existing="$(kt kafka-topics --bootstrap-server "$BOOTSTRAP_INTERNAL" --list 2>/dev/null)"
for p in 1 3 6 12; do
  grep -qx "perf-p$p" <<<"$existing" || kt kafka-topics --bootstrap-server "$BOOTSTRAP_INTERNAL" --create --topic "perf-p$p" \
     --partitions $p --replication-factor 3 --config min.insync.replicas=2 >/dev/null
done
sleep 3
echo "date: $(date -u +%FT%TZ)  records/run: $N  record size: 1KB  docker: $(docker info --format '{{.NCPU}} CPU, {{.MemTotal}} bytes')"

if [[ " $PARTS " == *" A "* ]]; then
banner "A1. Producer throughput vs partition count (acks=all, lz4, linger 5ms)"
for p in 1 3 6 12; do kcli bench-produce -topic perf-p$p -records "$N" -acks all -compression lz4 -linger 5ms -label "partitions=$p"; done
banner "A2. Consumer parallelism vs partition count (consumers = partitions, 1ms work/record, 12000 records)"
for p in 1 3 6 12; do kcli bench-consume -topic perf-p$p -consumers $p -records 12000 -work 1ms -label "partitions=$p"; done
fi

if [[ " $PARTS " == *" B "* ]]; then
banner "B. acks (perf-p6, lz4, linger 5ms)"
kcli bench-produce -topic perf-p6 -records "$N" -acks 0   -idempotent=false -compression lz4 -label "acks=0"
kcli bench-produce -topic perf-p6 -records "$N" -acks 1   -idempotent=false -compression lz4 -label "acks=1"
kcli bench-produce -topic perf-p6 -records "$N" -acks all -idempotent=true  -compression lz4 -label "acks=all (idempotent)"
fi

if [[ " $PARTS " == *" C "* ]]; then
banner "C. batching (perf-p6, acks=all, no compression)"
kcli bench-produce -topic perf-p6 -records "$N" -linger 0     -batch-bytes 16384   -label "linger=0 batch=16KB"
kcli bench-produce -topic perf-p6 -records "$N" -linger 5ms   -batch-bytes 1048576 -label "linger=5ms batch=1MB"
kcli bench-produce -topic perf-p6 -records "$N" -linger 20ms  -batch-bytes 1048576 -label "linger=20ms batch=1MB"
fi

if [[ " $PARTS " == *" D "* ]]; then
banner "D. compression (perf-p6, acks=all, linger 10ms, JSON payload)"
for c in none gzip snappy lz4 zstd; do kcli bench-produce -topic perf-p6 -records "$N" -compression $c -linger 10ms -label "compression=$c"; done
fi

if [[ " $PARTS " == *" E "* ]]; then
banner "E. consumer scaling on perf-p6 (6 partitions), 1ms work/record, 18000 records"
for c in 1 2 3 6 8; do kcli bench-consume -topic perf-p6 -consumers $c -records 18000 -work 1ms -label "consumers=$c" -v; done
fi

curl -s -X POST "localhost:8001/start?mode=constant&rate=5&duration=0s" >/dev/null
echo; echo "results saved to labs/performance/last-run.txt"
