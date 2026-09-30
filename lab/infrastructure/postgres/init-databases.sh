#!/bin/bash
set -euo pipefail
for service in vehicle warranty inspection repair; do
  password_var="${service^^}_DB_PASSWORD"
  psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname postgres \
    --set=service_role="${service}_app" --set=db_name="${service}_db" \
    --set=service_password="${!password_var}" <<'SQL'
CREATE USER :"service_role" WITH PASSWORD :'service_password';
CREATE DATABASE :"db_name" OWNER :"service_role";
REVOKE CONNECT ON DATABASE :"db_name" FROM PUBLIC;
GRANT CONNECT ON DATABASE :"db_name" TO :"service_role";
SQL
done
