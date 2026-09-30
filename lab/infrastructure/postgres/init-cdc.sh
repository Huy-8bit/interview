#!/bin/bash
set -euo pipefail
# Application migrations have completed before this job. DBA owns publications;
# Debezium receives SELECT/REPLICATION, not application ownership or superuser.
for entry in vehicle:vehicles warranty:warranties inspection:inspections repair:repair_requests; do
  service=${entry%%:*}
  table=${entry#*:}
  psql -v ON_ERROR_STOP=1 -d "${service}_db" -v table="$table" -v pub="dbz_${service}" <<'SQL'
ALTER TABLE public.:"table" REPLICA IDENTITY FULL;
GRANT SELECT ON public.:"table" TO debezium;
CREATE TABLE IF NOT EXISTS public.cdc_heartbeat (id integer PRIMARY KEY, updated_at timestamptz NOT NULL);
GRANT SELECT, INSERT, UPDATE ON public.cdc_heartbeat TO debezium;
SELECT format('CREATE PUBLICATION %I', :'pub') WHERE NOT EXISTS
  (SELECT FROM pg_publication WHERE pubname=:'pub') \gexec
ALTER PUBLICATION :"pub" SET TABLE public.:"table", public.cdc_heartbeat;
SQL
done
