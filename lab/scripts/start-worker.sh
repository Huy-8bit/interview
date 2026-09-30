#!/bin/sh
set -eu
# Prefork children write metric files here; stale files from a previous container
# run would otherwise be summed into the new process's counters.
rm -rf "$PROMETHEUS_MULTIPROC_DIR"
mkdir -p "$PROMETHEUS_MULTIPROC_DIR"
printf '[startup][%s] RUNNING Celery worker on %s (concurrency %s)\n' "${SERVICE_NAME:-worker}" "$REPORT_QUEUE" "$REPORT_WORKER_CONCURRENCY"
# Gossip/mingle/heartbeat need broadcast event traffic; this worker needs none of it.
exec celery -A app.reports.worker:celery_app worker \
  --queues "$REPORT_QUEUE" --pool prefork --concurrency "$REPORT_WORKER_CONCURRENCY" \
  --hostname "report-worker@%h" --without-gossip --without-mingle --without-heartbeat \
  --loglevel "${LOG_LEVEL:-INFO}"
