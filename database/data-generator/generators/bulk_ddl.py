"""Bulk-load mode: drop secondary indexes / UNIQUE / FOREIGN KEY constraints before
the load and rebuild them afterwards.

Why: with millions of rows, indexes on random keys (orders.user_id,
order_items.product_id, payments.transaction_id uuid, ...) outgrow memory and every
COPY batch turns into random I/O plus full-page images in WAL (measured: ~1,400
orders/s at 5M rows instead of ~14,000). Building an index once with a sort, and
validating a foreign key with one join, is an order of magnitude cheaper.

Safety: the DDL is stored in data_generator_runs.deferred_ddl BEFORE anything is
dropped. If the generator dies mid-load, the next run re-creates whatever is still
missing (restore_pending), so the schema can never silently lose an index or FK.
Primary keys and CHECK constraints are kept (ids are inserted in ascending order,
so the PK indexes stay cheap).
"""

from __future__ import annotations

import json
import time

import psycopg

# Indexes the generator itself reads through during the load: keep them.
KEEP_INDEXES = {"ux_addresses_one_default_per_user"}

# "%%" is a literal percent sign for format(): this query also has psycopg parameters
CAPTURE_SQL = """
SELECT 'fk' AS kind, c.conname AS name, c.conrelid::regclass::text AS table_name,
       format('ALTER TABLE %%s ADD CONSTRAINT %%I %%s', c.conrelid::regclass, c.conname,
              pg_get_constraintdef(c.oid)) AS ddl
FROM pg_constraint c
WHERE c.contype = 'f' AND c.conrelid::regclass::text = ANY(%(tables)s)
UNION ALL
SELECT 'unique', c.conname, c.conrelid::regclass::text,
       format('ALTER TABLE %%s ADD CONSTRAINT %%I %%s', c.conrelid::regclass, c.conname,
              pg_get_constraintdef(c.oid))
FROM pg_constraint c
WHERE c.contype = 'u' AND c.conrelid::regclass::text = ANY(%(tables)s)
UNION ALL
SELECT 'index', i.indexrelid::regclass::text, i.indrelid::regclass::text, pg_get_indexdef(i.indexrelid)
FROM pg_index i
WHERE i.indrelid::regclass::text = ANY(%(tables)s)
  AND NOT i.indisprimary
  AND NOT EXISTS (SELECT 1 FROM pg_constraint c WHERE c.conindid = i.indexrelid)
  AND i.indexrelid::regclass::text <> ALL(%(keep)s)
"""

# Rebuild order: plain indexes and UNIQUE constraints first, foreign keys last.
_REBUILD_ORDER = {"index": 0, "unique": 1, "fk": 2}


def _ensure_column(conn: psycopg.Connection) -> None:
    with conn.cursor() as cur:
        cur.execute("ALTER TABLE data_generator_runs ADD COLUMN IF NOT EXISTS deferred_ddl jsonb")
    conn.commit()


def _exists(cur, item: dict) -> bool:
    if item["kind"] == "index":
        cur.execute("SELECT to_regclass(%s) IS NOT NULL", (item["name"],))
    else:
        cur.execute("SELECT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = %s AND conrelid = %s::regclass)",
                    (item["name"], item["table"]))
    return cur.fetchone()[0]


def _rebuild(conn: psycopg.Connection, items: list[dict], label: str) -> None:
    items = sorted(items, key=lambda it: _REBUILD_ORDER[it["kind"]])
    print(f"{label}: {len(items)} indexes / constraints...", flush=True)
    started = time.perf_counter()
    with conn.cursor() as cur:
        # Bigger sort memory + parallel workers for CREATE INDEX (this session only)
        cur.execute("SET maintenance_work_mem = '512MB'")
        cur.execute("SET max_parallel_maintenance_workers = 4")
        for item in items:
            if _exists(cur, item):
                continue
            t0 = time.perf_counter()
            cur.execute(item["ddl"])
            conn.commit()
            print(f"  {item['kind']:<6} {item['name']:<40} {time.perf_counter() - t0:6.1f}s", flush=True)
    print(f"  done in {time.perf_counter() - started:.1f}s", flush=True)


def restore_pending(conn: psycopg.Connection) -> None:
    """Re-create objects left dropped by an interrupted run (no-op normally)."""
    _ensure_column(conn)
    with conn.cursor() as cur:
        cur.execute("SELECT id, deferred_ddl FROM data_generator_runs WHERE deferred_ddl IS NOT NULL ORDER BY id")
        pending = cur.fetchall()
    for run_id, items in pending:
        _rebuild(conn, items, f"Restoring DDL left by interrupted run #{run_id}")
        with conn.cursor() as cur:
            cur.execute("UPDATE data_generator_runs SET deferred_ddl = NULL WHERE id = %s", (run_id,))
        conn.commit()


def drop_for_load(conn: psycopg.Connection, run_id: int, tables: tuple[str, ...]) -> list[dict]:
    """Record, then drop, FKs / UNIQUE constraints / secondary indexes of `tables`."""
    _ensure_column(conn)
    with conn.cursor() as cur:
        cur.execute(CAPTURE_SQL, {"tables": list(tables), "keep": sorted(KEEP_INDEXES)})
        items = [{"kind": k, "name": n, "table": t, "ddl": d} for k, n, t, d in cur.fetchall()]
        # persisted (and committed) before the first DROP
        cur.execute("UPDATE data_generator_runs SET deferred_ddl = %s WHERE id = %s", (json.dumps(items), run_id))
    conn.commit()

    print(f"Bulk-load mode: dropping {len(items)} secondary indexes / UNIQUE / FK constraints "
          f"(rebuilt after the load)...", flush=True)
    with conn.cursor() as cur:
        for item in sorted(items, key=lambda it: -_REBUILD_ORDER[it["kind"]]):     # FKs first
            if item["kind"] == "index":
                cur.execute(f"DROP INDEX IF EXISTS {item['name']}")
            else:
                cur.execute(f"ALTER TABLE {item['table']} DROP CONSTRAINT IF EXISTS {item['name']}")
    conn.commit()
    return items


def rebuild_after_load(conn: psycopg.Connection, run_id: int, items: list[dict]) -> None:
    """Build indexes, re-add UNIQUE constraints and FOREIGN KEYs (validates every row)."""
    _rebuild(conn, items, "Rebuilding")
    with conn.cursor() as cur:
        cur.execute("UPDATE data_generator_runs SET deferred_ddl = NULL WHERE id = %s", (run_id,))
    conn.commit()
