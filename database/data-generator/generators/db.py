"""Database helpers: connection, COPY loader, progress logging."""

from __future__ import annotations

import time
from typing import Iterable, Sequence

import psycopg
from psycopg import sql

from .config import Config


def connect(cfg: Config, retries: int = 30, delay: float = 2.0) -> psycopg.Connection:
    """Connect to the primary, retrying while it is still starting up."""
    last_error: Exception | None = None
    for attempt in range(1, retries + 1):
        try:
            return psycopg.connect(cfg.conninfo(), autocommit=False)
        except psycopg.OperationalError as exc:
            last_error = exc
            print(f"  database not ready ({attempt}/{retries}): {exc}".strip(), flush=True)
            time.sleep(delay)
    raise RuntimeError(f"could not connect to {cfg.db_host}:{cfg.db_port}") from last_error


def copy_rows(conn: psycopg.Connection, table: str, columns: Sequence[str], rows: Iterable[Sequence]) -> int:
    """Bulk-load rows with COPY ... FROM STDIN (far faster than INSERT).

    COPY streams all rows in a single command: one parse/plan, no per-row
    round trips, and WAL is written in large chunks.
    """
    stmt = sql.SQL("COPY {} ({}) FROM STDIN").format(
        sql.Identifier(table), sql.SQL(", ").join(map(sql.Identifier, columns))
    )
    count = 0
    with conn.cursor() as cur, cur.copy(stmt) as copy:
        for row in rows:
            copy.write_row(row)
            count += 1
    return count


class Progress:
    """Prints `Label: done / total` lines, e.g. `Users: 20000 / 100000`."""

    def __init__(self, label: str, total: int):
        self.label = label
        self.total = total
        self.done = 0
        self.started = time.perf_counter()
        print(f"Generating {label.lower()}...", flush=True)

    def advance(self, n: int) -> None:
        self.done += n
        elapsed = time.perf_counter() - self.started
        rate = self.done / elapsed if elapsed > 0 else 0.0
        print(f"  {self.label}: {self.done} / {self.total}   ({elapsed:6.1f}s, {rate:,.0f} rows/s)", flush=True)

    def finish(self, extra: str = "") -> None:
        elapsed = time.perf_counter() - self.started
        suffix = f" - {extra}" if extra else ""
        print(f"  {self.label}: done, {self.done:,} rows in {elapsed:.1f}s{suffix}", flush=True)
