"""Entry point: generate realistic e-commerce data into the PRIMARY with COPY.

    docker compose run --rm data-generator                    # generate if empty
    docker compose run --rm -e RESET_DATA=true data-generator # wipe + regenerate
    docker compose run --rm -e NUM_ORDERS=50000 -e NUM_ORDER_ITEMS=150000 -e RESET_DATA=true data-generator
"""

from __future__ import annotations

import json
import sys
import time
from dataclasses import asdict
from datetime import datetime, timezone

import psycopg

from generators.catalog import generate_catalog
from generators.config import Config
from generators.context import Context
from generators.db import connect
from generators.orders import generate_orders
from generators.products import generate_products
from generators.reviews import generate_reviews
from generators.users import generate_users

DATA_TABLES = ("reviews", "payments", "order_items", "orders", "inventory", "products", "warehouses",
               "addresses", "users", "categories")
# Tables whose ids the generator supplies explicitly -> identity sequence must be re-synced
EXPLICIT_ID_TABLES = ("users", "categories", "warehouses", "products", "orders")


def _has_completed_run(conn: psycopg.Connection) -> bool:
    with conn.cursor() as cur:
        cur.execute("SELECT EXISTS (SELECT 1 FROM data_generator_runs WHERE status = 'COMPLETED')")
        return cur.fetchone()[0]


def _has_data(conn: psycopg.Connection) -> bool:
    with conn.cursor() as cur:
        cur.execute("SELECT EXISTS (SELECT 1 FROM users) OR EXISTS (SELECT 1 FROM categories)")
        return cur.fetchone()[0]


def _truncate(conn: psycopg.Connection) -> None:
    print("Truncating existing data (TRUNCATE ... RESTART IDENTITY CASCADE)...", flush=True)
    with conn.cursor() as cur:
        cur.execute(f"TRUNCATE {', '.join(DATA_TABLES)} RESTART IDENTITY CASCADE")
    conn.commit()


def _finalize(cfg: Config) -> dict[str, int]:
    """Re-sync sequences, then VACUUM ANALYZE (fresh planner statistics + visibility map
    so Index Only Scans work right away). VACUUM cannot run inside a transaction."""
    print("Finalizing: syncing identity sequences, VACUUM ANALYZE...", flush=True)
    with psycopg.connect(cfg.conninfo(), autocommit=True) as conn, conn.cursor() as cur:
        for table in EXPLICIT_ID_TABLES:
            cur.execute(
                f"SELECT setval(pg_get_serial_sequence('{table}', 'id'), "
                f"COALESCE((SELECT max(id) FROM {table}), 0) + 1, false)"
            )
        for table in DATA_TABLES:
            started = time.perf_counter()
            cur.execute(f"VACUUM (ANALYZE) {table}")
            print(f"  VACUUM (ANALYZE) {table}: {time.perf_counter() - started:.1f}s", flush=True)
        counts = {}
        for table in reversed(DATA_TABLES):
            cur.execute(f"SELECT count(*) FROM {table}")
            counts[table] = cur.fetchone()[0]
        return counts


def _print_summary(cfg: Config, counts: dict[str, int], elapsed: float) -> None:
    with psycopg.connect(cfg.conninfo(), autocommit=True) as conn, conn.cursor() as cur:
        cur.execute("SELECT pg_size_pretty(pg_database_size(current_database()))")
        db_size = cur.fetchone()[0]
    print("\n" + "=" * 60)
    print(f"Data generation completed in {elapsed / 60:.1f} min  (database size: {db_size})")
    print("=" * 60)
    for table, count in counts.items():
        print(f"  {table:<14} {count:>12,}")
    print("=" * 60, flush=True)


def main() -> int:
    cfg = Config.from_env()
    settings = {k: v for k, v in asdict(cfg).items() if k != "db_password"}
    print("Data generator settings:\n" + json.dumps(settings, indent=2), flush=True)

    if not cfg.auto_generate:
        print("AUTO_GENERATE=false -> nothing to do.")
        return 0

    conn = connect(cfg)
    if _has_completed_run(conn) and not cfg.reset_data:
        print("Data already generated (data_generator_runs has a COMPLETED run) -> skipping.\n"
              "Use RESET_DATA=true to wipe and regenerate:\n"
              "  docker compose run --rm -e RESET_DATA=true data-generator")
        return 0
    if cfg.reset_data or _has_data(conn):
        if not cfg.reset_data:
            print("Found data from an unfinished run -> starting over.")
        _truncate(conn)

    with conn.cursor() as cur:
        cur.execute("INSERT INTO data_generator_runs (status, settings) VALUES ('RUNNING', %s) RETURNING id",
                    (json.dumps(settings),))
        run_id = cur.fetchone()[0]
    conn.commit()

    started = time.perf_counter()
    try:
        ctx = Context.create(cfg, conn, now=datetime.now(timezone.utc).replace(microsecond=0))
        catalog = generate_catalog(ctx)
        users = generate_users(ctx)
        products = generate_products(ctx, catalog)
        purchases = generate_orders(ctx, users, products)
        generate_reviews(ctx, users, products, purchases)
        counts = _finalize(cfg)
    except Exception as exc:
        conn.rollback()
        with conn.cursor() as cur:
            cur.execute("UPDATE data_generator_runs SET status = 'FAILED', error = %s, finished_at = now() "
                        "WHERE id = %s", (repr(exc), run_id))
        conn.commit()
        raise

    with conn.cursor() as cur:
        cur.execute("UPDATE data_generator_runs SET status = 'COMPLETED', row_counts = %s, finished_at = now() "
                    "WHERE id = %s", (json.dumps(counts), run_id))
    conn.commit()
    conn.close()
    _print_summary(cfg, counts, time.perf_counter() - started)
    return 0


if __name__ == "__main__":
    sys.exit(main())
