-- =============================================================================
-- Lab 24 · DISTINCT: full scan vs emulated skip scan, count(DISTINCT) — OPTIMIZE · Strategy A
-- Strategy A: Rewrite Q1 as a recursive 'skip scan' (loose index scan emulation)
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

-- What / why:
-- PostgreSQL 16 has no skip scan. A recursive CTE can emulate it: find the
-- smallest category_id, then repeatedly 'the smallest value greater than the
-- previous one' - each step is ONE index descent (LIMIT 1). 40 values = ~41
-- tiny index lookups instead of reading 5M entries.

-- -----------------------------------------------------------------------------
-- Q1 as a recursive skip scan
-- -----------------------------------------------------------------------------

-- 1) The query itself
WITH RECURSIVE c AS (
  (SELECT category_id FROM products ORDER BY category_id LIMIT 1)
  UNION ALL
  SELECT (SELECT p.category_id FROM products p
          WHERE p.category_id > c.category_id
          ORDER BY p.category_id LIMIT 1)
  FROM c
  WHERE c.category_id IS NOT NULL
)
SELECT category_id FROM c WHERE category_id IS NOT NULL;

-- 2) EXPLAIN: plan + ESTIMATES only. The query is NOT executed.
EXPLAIN
WITH RECURSIVE c AS (
  (SELECT category_id FROM products ORDER BY category_id LIMIT 1)
  UNION ALL
  SELECT (SELECT p.category_id FROM products p
          WHERE p.category_id > c.category_id
          ORDER BY p.category_id LIMIT 1)
  FROM c
  WHERE c.category_id IS NOT NULL
)
SELECT category_id FROM c WHERE category_id IS NOT NULL;

-- 3) EXPLAIN ANALYZE: EXECUTES the query, adds actual time / rows / loops.
EXPLAIN ANALYZE
WITH RECURSIVE c AS (
  (SELECT category_id FROM products ORDER BY category_id LIMIT 1)
  UNION ALL
  SELECT (SELECT p.category_id FROM products p
          WHERE p.category_id > c.category_id
          ORDER BY p.category_id LIMIT 1)
  FROM c
  WHERE c.category_id IS NOT NULL
)
SELECT category_id FROM c WHERE category_id IS NOT NULL;

-- 4) Full detail: buffers (I/O), output columns, non-default settings.
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS)
WITH RECURSIVE c AS (
  (SELECT category_id FROM products ORDER BY category_id LIMIT 1)
  UNION ALL
  SELECT (SELECT p.category_id FROM products p
          WHERE p.category_id > c.category_id
          ORDER BY p.category_id LIMIT 1)
  FROM c
  WHERE c.category_id IS NOT NULL
)
SELECT category_id FROM c WHERE category_id IS NOT NULL;

-- Observe:
--   * Recursive Union -> SubPlan with Limit + Index Only Scan, loops=41

-- Undo only this strategy:
-- -- (nothing to undo: query rewrite only)

-- Next: run 05_reset.sql, compare with 01_before.sql, then 05_reset.sql.
