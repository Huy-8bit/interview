-- =============================================================================
-- Lab 12 · JSONB: GIN jsonb_ops vs jsonb_path_ops vs expression B-tree — AFTER
-- Same query again, with the optimization applied (02_optimize.sql or 02b/02c...).
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Q1. Containment: users tagged 'wholesale' (~15k of 5M)
-- -----------------------------------------------------------------------------

-- 1) The query itself
SELECT count(*)
FROM users
WHERE metadata @> '{"tags": ["wholesale"]}';

-- 2) EXPLAIN: plan + ESTIMATES only. The query is NOT executed.
EXPLAIN
SELECT count(*)
FROM users
WHERE metadata @> '{"tags": ["wholesale"]}';

-- 3) EXPLAIN ANALYZE: EXECUTES the query, adds actual time / rows / loops.
EXPLAIN ANALYZE
SELECT count(*)
FROM users
WHERE metadata @> '{"tags": ["wholesale"]}';

-- 4) Full detail: buffers (I/O), output columns, non-default settings.
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS)
SELECT count(*)
FROM users
WHERE metadata @> '{"tags": ["wholesale"]}';

-- Observe:
--   * Seq Scan: every metadata document is parsed and checked

-- -----------------------------------------------------------------------------
-- Q2. Key existence: users with a 'referred_by' key (~8%)
-- -----------------------------------------------------------------------------

-- 1) The query itself
SELECT count(*)
FROM users
WHERE metadata ? 'referred_by';

-- 2) EXPLAIN: plan + ESTIMATES only. The query is NOT executed.
EXPLAIN
SELECT count(*)
FROM users
WHERE metadata ? 'referred_by';

-- 3) EXPLAIN ANALYZE: EXECUTES the query, adds actual time / rows / loops.
EXPLAIN ANALYZE
SELECT count(*)
FROM users
WHERE metadata ? 'referred_by';

-- 4) Full detail: buffers (I/O), output columns, non-default settings.
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS)
SELECT count(*)
FROM users
WHERE metadata ? 'referred_by';

-- -----------------------------------------------------------------------------
-- Q3. One scalar field: preferred_language = 'ja' (~3.8%)
-- -----------------------------------------------------------------------------

-- 1) The query itself
SELECT count(*)
FROM users
WHERE metadata ->> 'preferred_language' = 'ja';

-- 2) EXPLAIN: plan + ESTIMATES only. The query is NOT executed.
EXPLAIN
SELECT count(*)
FROM users
WHERE metadata ->> 'preferred_language' = 'ja';

-- 3) EXPLAIN ANALYZE: EXECUTES the query, adds actual time / rows / loops.
EXPLAIN ANALYZE
SELECT count(*)
FROM users
WHERE metadata ->> 'preferred_language' = 'ja';

-- 4) Full detail: buffers (I/O), output columns, non-default settings.
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS)
SELECT count(*)
FROM users
WHERE metadata ->> 'preferred_language' = 'ja';

-- Observe:
--   * ->> returns text: GIN indexes cannot serve this operator

-- Record the numbers in 04_compare.sql, then run 05_reset.sql.
