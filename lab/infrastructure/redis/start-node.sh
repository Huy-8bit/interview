#!/bin/sh
set -eu
# Stable addresses keep persisted nodes.conf valid after container recreation.
# Redis Cluster endpoints and bus ports are reachable only on the Docker network.
exec docker-entrypoint.sh redis-server \
  --bind 0.0.0.0 --protected-mode no --port 6379 \
  --dir /data --appendonly yes --appendfsync everysec \
  --cluster-enabled yes --cluster-config-file nodes.conf \
  --cluster-node-timeout 5000 --cluster-require-full-coverage yes \
  --cluster-announce-ip "$REDIS_NODE_IP" \
  --cluster-announce-hostname "$REDIS_NODE_NAME" \
  --cluster-announce-port 6379 --cluster-announce-bus-port 16379
