#!/usr/bin/env bash
# Runs INSIDE a Kafka container (kafka-init). Creates every topic from
# /topics/topics.conf and (re)applies its configs, so it is idempotent and also
# undoes config changes made by labs.
#   TOPICS_FILE   default /topics/topics.conf
#   ONLY_TOPICS   optional space separated subset
set -euo pipefail
BOOTSTRAP="${BOOTSTRAP:-kafka-1:29092,kafka-2:29092,kafka-3:29092}"
TOPICS_FILE="${TOPICS_FILE:-/topics/topics.conf}"
ONLY_TOPICS="${ONLY_TOPICS:-}"

echo "==> waiting for 3 registered brokers via ${BOOTSTRAP}"
for i in $(seq 1 60); do
  n=$(kt kafka-broker-api-versions --bootstrap-server "$BOOTSTRAP" 2>/dev/null | grep -c '(id:' || true)
  [[ "$n" -ge 3 ]] && break
  sleep 2
done
echo "    brokers visible: ${n}"

existing="$(kt kafka-topics --bootstrap-server "$BOOTSTRAP" --list 2>/dev/null || true)"

while read -r topic partitions rf configs; do
  [[ -z "${topic}" || "${topic}" == \#* ]] && continue
  if [[ -n "$ONLY_TOPICS" && " $ONLY_TOPICS " != *" $topic "* ]]; then continue; fi
  if grep -qx "$topic" <<<"$existing"; then
    echo "==> exists  $topic  (re-applying configs)"
    if [[ -n "${configs:-}" ]]; then
      kt kafka-configs --bootstrap-server "$BOOTSTRAP" --alter --entity-type topics \
        --entity-name "$topic" --add-config "$configs" >/dev/null
    fi
  else
    echo "==> create  $topic  partitions=$partitions rf=$rf ${configs:-}"
    args=(--bootstrap-server "$BOOTSTRAP" --create --if-not-exists --topic "$topic"
          --partitions "$partitions" --replication-factor "$rf")
    if [[ -n "${configs:-}" ]]; then
      IFS=',' read -ra kvs <<<"$configs"
      for kv in "${kvs[@]}"; do args+=(--config "$kv"); done
    fi
    kt kafka-topics "${args[@]}"
  fi
done <"$TOPICS_FILE"
echo "==> topics ready"
