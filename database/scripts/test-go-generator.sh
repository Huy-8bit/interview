#!/usr/bin/env bash
# Integration test in a disposable, network-isolated PG16 container on tmpfs.
# Never connects to the Compose primary/replica or mounts their volumes.
set -Eeuo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"
name="pglab-go-test-$$-$RANDOM"
image="postgresql-lab/data-generator-go:latest"
test_log="$(mktemp -d "${TMPDIR:-/tmp}/pglab-go-test.XXXXXX")"
cleanup() { docker rm -f "$name" >/dev/null 2>&1 || true; }
trap cleanup EXIT
docker build -q -t "$image" data-generator-go
docker run -d --rm --name "$name" --network none --tmpfs /var/lib/postgresql/data:rw \
  -e POSTGRES_PASSWORD=go-test-only -e POSTGRES_DB=generator_test postgres:16-alpine >/dev/null
ready=0
for attempt in {1..30}; do
  if docker exec "$name" pg_isready -h 127.0.0.1 -U postgres -d generator_test >/dev/null 2>&1; then ready=1; break; fi
  sleep 1
done
[ "$ready" -eq 1 ] || { echo "PostgreSQL test container did not become ready" >&2; exit 1; }
if docker run --rm --network "container:$name" \
  -e DB_HOST=127.0.0.1 -e DB_NAME=missing_generator_database -e DB_PASSWORD=go-test-only \
  "$image" small > "$test_log/missing-database.log" 2>&1; then
  echo "FAIL: nonexistent DB was accepted" >&2; exit 1
fi
rg -q 'SQLSTATE 3D000' "$test_log/missing-database.log"
rg -q 'DB_NAME=ecommerce' "$test_log/missing-database.log"
test_db=generator_test
psql_test() { docker exec -i "$name" psql -X -v ON_ERROR_STOP=1 -U postgres -d "$test_db" "$@"; }
schema_snapshot() {
  psql_test -Atc "SELECT conrelid::regclass,conname,pg_get_constraintdef(oid),convalidated FROM pg_constraint WHERE connamespace='public'::regnamespace ORDER BY 1,2; SELECT tablename,indexname,indexdef FROM pg_indexes WHERE schemaname='public' ORDER BY 1,2"
}
for mode in normal bulk; do
if [ "$mode" = bulk ]; then
  test_db=generator_bulk
  docker exec "$name" createdb -U postgres "$test_db"
fi
psql_test -q < postgres/primary/init/03-schema.sql
psql_test -q < postgres/primary/init/04-indexes.sql
schema_snapshot > "$test_log/$mode-schema-before.txt"
generate() {
  docker run --rm --network "container:$name" \
    -e DB_HOST=127.0.0.1 -e DB_NAME="$test_db" -e DB_PASSWORD=go-test-only \
    -e NUM_USERS=100 -e NUM_PRODUCTS=100 -e NUM_INVENTORY=250 \
    -e NUM_ORDERS=500 -e NUM_ORDER_ITEMS=1501 -e NUM_REVIEWS=300 \
    "$image" custom --batch-size 37 --data-now 2026-10-01T00:00:00Z "$@"
}
if [ "$mode" = bulk ]; then
  generate --bulk-load --analyze > "$test_log/$mode-generation.log"
else
  generate --analyze > "$test_log/$mode-generation.log"
fi
schema_snapshot > "$test_log/$mode-schema-after.txt"
diff -u "$test_log/$mode-schema-before.txt" "$test_log/$mode-schema-after.txt"
psql_test < sql/verify/data-quality.sql > "$test_log/$mode-quality.log"
if [ "$(awk '/\| *PASS *$/ {n++} END {print n+0}' "$test_log/$mode-quality.log")" -ne 17 ] || rg -q '\| *FAIL *$' "$test_log/$mode-quality.log"; then
  cat "$test_log/$mode-quality.log"; exit 1
fi
# Fingerprint every row, the run log and sequence state before a refused retry.
snapshot() {
  for table in categories warehouses users addresses products inventory orders order_items payments reviews data_generator_runs; do
    psql_test -Atc "SELECT '$table', count(*), sum(hashtextextended(t::text,0)::numeric) FROM $table t"
  done
  psql_test -Atc "SELECT sequencename,last_value FROM pg_sequences WHERE schemaname='public' ORDER BY sequencename"
}
snapshot > "$test_log/before.txt"
if generate --bulk-load > "$test_log/retry.log" 2>&1; then echo "FAIL: occupied DB was accepted" >&2; exit 1; fi
rg -q 'database contains data' "$test_log/retry.log"
snapshot > "$test_log/after.txt"
diff -u "$test_log/before.txt" "$test_log/after.txt"
# Omitted-ID inserts must allocate beyond all explicit generated IDs.
[ "$(psql_test -Atc "SELECT nextval('users_id_seq'),nextval('products_id_seq'),nextval('orders_id_seq')")" = '101|101|501' ]
done
# Simulate an interrupted bulk run with persisted DDL, then restore twice to
# prove crash recovery is idempotent and does not generate or remove data.
psql_test -q <<'SQL'
INSERT INTO data_generator_runs(status,settings,deferred_ddl)
SELECT 'RUNNING','{"Engine":"go"}',jsonb_build_array(jsonb_build_object(
  'kind','index','name',indexname,'table',tablename,'ddl',indexdef))
FROM pg_indexes WHERE schemaname='public' AND indexname='idx_products_price';
DROP INDEX idx_products_price;
SQL
snapshot | awk '!/^data_generator_runs\|/' > "$test_log/before-recovery-data.txt"
generate --restore-schema > "$test_log/restore.log"
generate --restore-schema >> "$test_log/restore.log"
schema_snapshot > "$test_log/restored-schema.txt"
diff -u "$test_log/bulk-schema-before.txt" "$test_log/restored-schema.txt"
snapshot | awk '!/^data_generator_runs\|/' > "$test_log/after-recovery-data.txt"
diff -u "$test_log/before-recovery-data.txt" "$test_log/after-recovery-data.txt"
[ "$(psql_test -Atc "SELECT count(*) FROM data_generator_runs WHERE deferred_ddl IS NOT NULL OR status='RUNNING'")" = 0 ]
echo "PASS: normal/bulk modes, 17 quality checks each, schema equality, occupied-DB refusal, unchanged rows/sequences, identity allocation, idempotent recovery. Logs: $test_log"
