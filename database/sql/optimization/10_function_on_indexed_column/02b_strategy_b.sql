-- =============================================================================
-- Lab 10 · Function on an indexed column (sargable queries) — OPTIMIZE · Strategy B
-- Strategy B: Expression index on the UTC date (when the query cannot be changed)
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

-- Start from the baseline: run 05_reset.sql first if another strategy is still applied.

-- What / why:
-- created_at::date is NOT immutable (timestamptz -> date depends on the TimeZone
-- setting), so it cannot be indexed. (created_at AT TIME ZONE 'UTC')::date is
-- immutable and can. The query must then use exactly that expression.

-- This fails on purpose: the cast depends on the session TimeZone
DO $$
BEGIN
  EXECUTE 'CREATE INDEX ix_lab10_should_fail ON orders ((created_at::date))';
EXCEPTION WHEN others THEN
  RAISE NOTICE 'expected error: %', SQLERRM;
END $$;

CREATE INDEX ix_lab10_orders_created_utc_date ON orders (((created_at AT TIME ZONE 'UTC')::date));
ANALYZE orders;

-- -----------------------------------------------------------------------------
-- Query using the indexed expression
-- -----------------------------------------------------------------------------

-- 1) The query itself
SELECT count(*)
FROM orders
WHERE (created_at AT TIME ZONE 'UTC')::date = '2026-06-15';

-- 2) EXPLAIN: plan + ESTIMATES only. The query is NOT executed.
EXPLAIN
SELECT count(*)
FROM orders
WHERE (created_at AT TIME ZONE 'UTC')::date = '2026-06-15';

-- 3) EXPLAIN ANALYZE: EXECUTES the query, adds actual time / rows / loops.
EXPLAIN ANALYZE
SELECT count(*)
FROM orders
WHERE (created_at AT TIME ZONE 'UTC')::date = '2026-06-15';

-- 4) Full detail: buffers (I/O), output columns, non-default settings.
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS)
SELECT count(*)
FROM orders
WHERE (created_at AT TIME ZONE 'UTC')::date = '2026-06-15';

-- Observe:
--   * Index (Only) Scan using ix_lab10_orders_created_utc_date

-- Check what was created / changed:
SELECT indexname, pg_size_pretty(pg_relation_size(format('%I', indexname)::regclass)) AS size
FROM pg_indexes WHERE tablename = 'orders' ORDER BY 1;

-- Undo only this strategy:
-- DROP INDEX IF EXISTS ix_lab10_orders_created_utc_date;

-- Next: run 05_reset.sql, compare with 01_before.sql, then 05_reset.sql.
