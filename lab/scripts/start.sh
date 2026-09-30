#!/bin/sh
set -eu
printf '[startup][%s][1/2] RUNNING Alembic migrations\n' "${SERVICE_NAME:-app}"
if alembic upgrade head; then
  printf '[startup][%s][1/2] OK Database migrations completed\n' "${SERVICE_NAME:-app}"
else
  status=$?
  printf '[startup][%s][1/2] FAILED Alembic migrations (exit %s)\n' "${SERVICE_NAME:-app}" "$status" >&2
  exit "$status"
fi
printf '[startup][%s][2/2] RUNNING Uvicorn and lifespan workers; Docker healthcheck waits for /ready\n' "${SERVICE_NAME:-app}"
exec uvicorn app.main:app --host 0.0.0.0 --port 8000 --no-access-log
