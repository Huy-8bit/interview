-- =============================================================================
-- Lab 11 · Implicit casts that disable an index — OPTIMIZE · Strategy B
-- Strategy B: See the type resolution: errors and quoted literals
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

-- Start from the baseline: run 05_reset.sql first if another strategy is still applied.

-- What / why:
-- An untyped quoted literal ('250000') takes the column's type - safe. A typed
-- literal or parameter forces a conversion. Some combinations are not even
-- allowed (varchar = integer): better an error than a silent Seq Scan.

SELECT pg_typeof(250000) AS int_literal, pg_typeof(250000.0) AS numeric_literal,
       pg_typeof('250000') AS untyped_literal;

DO $$
BEGIN
  PERFORM 1 FROM orders WHERE order_number = 250000;
EXCEPTION WHEN others THEN
  RAISE NOTICE 'expected error: %', SQLERRM;
END $$;

-- -----------------------------------------------------------------------------
-- Untyped string literal takes the column type (index used)
-- -----------------------------------------------------------------------------

-- 1) The query itself
SELECT id, order_number, total_amount
FROM orders
WHERE id = '250000';

-- 2) EXPLAIN: plan + ESTIMATES only. The query is NOT executed.
EXPLAIN
SELECT id, order_number, total_amount
FROM orders
WHERE id = '250000';

-- 3) EXPLAIN ANALYZE: EXECUTES the query, adds actual time / rows / loops.
EXPLAIN ANALYZE
SELECT id, order_number, total_amount
FROM orders
WHERE id = '250000';

-- 4) Full detail: buffers (I/O), output columns, non-default settings.
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS)
SELECT id, order_number, total_amount
FROM orders
WHERE id = '250000';

-- Observe:
--   * Index Cond: (id = '250000'::bigint)

-- Undo only this strategy:
-- -- (nothing to undo)

-- Next: run 05_reset.sql, compare with 01_before.sql, then 05_reset.sql.
