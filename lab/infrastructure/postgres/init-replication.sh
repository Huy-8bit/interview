#!/bin/bash
set -euo pipefail
# Runs on every Compose initialization, including an existing primary volume.
psql -v ON_ERROR_STOP=1 -d postgres \
  -v replication_password="$REPLICATION_PASSWORD" -v cdc_password="$DEBEZIUM_PASSWORD" <<'SQL'
SELECT 'CREATE ROLE replicator LOGIN REPLICATION' WHERE NOT EXISTS
  (SELECT FROM pg_roles WHERE rolname='replicator') \gexec
ALTER ROLE replicator WITH LOGIN REPLICATION NOSUPERUSER PASSWORD :'replication_password';
SELECT 'CREATE ROLE debezium LOGIN REPLICATION' WHERE NOT EXISTS
  (SELECT FROM pg_roles WHERE rolname='debezium') \gexec
ALTER ROLE debezium WITH LOGIN REPLICATION NOSUPERUSER PASSWORD :'cdc_password';
SELECT pg_create_physical_replication_slot('lab_physical_replica', true)
WHERE NOT EXISTS (SELECT FROM pg_replication_slots WHERE slot_name='lab_physical_replica');
SQL
for service in vehicle warranty inspection repair; do
  password_var="${service^^}_READ_PASSWORD"
  psql -v ON_ERROR_STOP=1 -d "${service}_db" -v reader="${service}_reader" \
    -v owner="${service}_app" -v db="${service}_db" -v password="${!password_var}" <<'SQL'
SELECT format('CREATE ROLE %I LOGIN', :'reader') WHERE NOT EXISTS
  (SELECT FROM pg_roles WHERE rolname=:'reader') \gexec
ALTER ROLE :"reader" WITH LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE PASSWORD :'password';
ALTER ROLE :"reader" SET default_transaction_read_only = on;
GRANT CONNECT ON DATABASE :"db" TO :"reader", debezium;
GRANT USAGE ON SCHEMA public TO :"reader", debezium;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO :"reader";
ALTER DEFAULT PRIVILEGES FOR ROLE :"owner" IN SCHEMA public GRANT SELECT ON TABLES TO :"reader";
SQL
done
