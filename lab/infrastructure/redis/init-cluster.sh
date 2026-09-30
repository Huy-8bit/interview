#!/bin/sh
set -eu
prefix="${REDIS_SUBNET_PREFIX:-172.29.86}"
node_info() { redis-cli -h "$1" --raw cluster info | tr -d '\r'; }
# Compose checks PING on all nodes. Never reset an existing or partially formed cluster.
empty=0
for i in 11 12 13 14 15 16; do
  info=$(node_info "$prefix.$i")
  if echo "$info" | grep -qx 'cluster_known_nodes:1' && echo "$info" | grep -qx 'cluster_slots_assigned:0'; then
    empty=$((empty + 1))
  fi
done
if [ "$empty" -eq 6 ]; then
  redis-cli --cluster create \
    "$prefix.11:6379" "$prefix.12:6379" "$prefix.13:6379" \
    "$prefix.14:6379" "$prefix.15:6379" "$prefix.16:6379" \
    --cluster-replicas 1 --cluster-yes
fi
# Bounded condition polling, including replica links; initial PING is not cluster readiness.
for attempt in $(seq 1 120); do
  ready=0
  for i in 11 12 13 14 15 16; do
    info=$(node_info "$prefix.$i")
    if echo "$info" | grep -qx 'cluster_state:ok' && \
       echo "$info" | grep -qx 'cluster_slots_ok:16384' && \
       echo "$info" | grep -qx 'cluster_known_nodes:6' && \
       echo "$info" | grep -qx 'cluster_size:3'; then
      ready=$((ready + 1))
    fi
  done
  nodes=$(redis-cli -h "$prefix.11" --raw cluster nodes)
  masters=$(echo "$nodes" | awk '$3 ~ /master/ {n++} END {print n+0}')
  replicas=$(echo "$nodes" | awk '$3 ~ /slave/ {n++} END {print n+0}')
  links=0
  for i in 11 12 13 14 15 16; do
    if redis-cli -h "$prefix.$i" --raw info replication | tr -d '\r' | grep -qx 'master_link_status:up'; then
      links=$((links + 1))
    fi
  done
  if [ "$ready" -eq 6 ] && [ "$masters" -eq 3 ] && [ "$replicas" -eq 3 ] && [ "$links" -eq 3 ]; then
    echo 'Redis Cluster ready: 16384 slots, 3 masters, 3 connected replicas'
    echo "$nodes"
    exit 0
  fi
  sleep 1
done
echo 'Redis Cluster did not become healthy; inspect nodes/volumes. No data was reset.' >&2
exit 1
