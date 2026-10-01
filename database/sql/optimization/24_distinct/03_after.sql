-- =============================================================================
-- Lab 24 · DISTINCT: full scan vs emulated skip scan, count(DISTINCT) — AFTER
-- Both rewrites together (the recommended versions of Q1 and Q2).
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Q1. Q1 as a recursive skip scan
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

-- -----------------------------------------------------------------------------
-- Q2. Q2 rewritten
-- -----------------------------------------------------------------------------

-- 1) The query itself
SELECT count(*)
FROM (SELECT DISTINCT user_id FROM orders WHERE created_at >= '2026-09-01') s;

-- 2) EXPLAIN: plan + ESTIMATES only. The query is NOT executed.
EXPLAIN
SELECT count(*)
FROM (SELECT DISTINCT user_id FROM orders WHERE created_at >= '2026-09-01') s;

-- 3) EXPLAIN ANALYZE: EXECUTES the query, adds actual time / rows / loops.
EXPLAIN ANALYZE
SELECT count(*)
FROM (SELECT DISTINCT user_id FROM orders WHERE created_at >= '2026-09-01') s;

-- 4) Full detail: buffers (I/O), output columns, non-default settings.
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS)
SELECT count(*)
FROM (SELECT DISTINCT user_id FROM orders WHERE created_at >= '2026-09-01') s;

-- Record the numbers in 04_compare.sql, then run 05_reset.sql.
