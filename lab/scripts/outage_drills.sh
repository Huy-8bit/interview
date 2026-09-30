#!/bin/sh
# Run only against this disposable lab stack. Every stopped container is restored.
set -eu
component="${1:-kafka}"
case "$component" in postgres|redis|kafka|warranty-service) ;; *) echo 'Usage: sh scripts/outage_drills.sh postgres|redis|kafka|warranty-service' >&2; exit 2;; esac
docker compose build toolbox
restore() { docker compose start "$component"; }
trap restore EXIT INT TERM
docker compose stop "$component"
docker compose run --rm --no-deps toolbox python scripts/outage_probe.py "$component"
restore
trap - EXIT INT TERM
docker compose run --rm --no-deps toolbox python scripts/outage_probe.py recovery
