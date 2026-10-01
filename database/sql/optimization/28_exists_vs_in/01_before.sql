-- =============================================================================
-- Lab 28 · EXISTS vs IN, NOT EXISTS vs NOT IN (and the NULL trap) — BEFORE (baseline)
-- The query as it runs today, before any optimization.
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Q1. IN: customers who ordered on the last day
-- -----------------------------------------------------------------------------

-- 1) The query itself
SELECT count(*)
FROM users u
WHERE u.id IN (SELECT o.user_id FROM orders o WHERE o.created_at >= '2026-09-30');

-- 2) EXPLAIN: plan + ESTIMATES only. The query is NOT executed.
EXPLAIN
SELECT count(*)
FROM users u
WHERE u.id IN (SELECT o.user_id FROM orders o WHERE o.created_at >= '2026-09-30');

-- 3) EXPLAIN ANALYZE: EXECUTES the query, adds actual time / rows / loops.
EXPLAIN ANALYZE
SELECT count(*)
FROM users u
WHERE u.id IN (SELECT o.user_id FROM orders o WHERE o.created_at >= '2026-09-30');

-- 4) Full detail: buffers (I/O), output columns, non-default settings.
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS)
SELECT count(*)
FROM users u
WHERE u.id IN (SELECT o.user_id FROM orders o WHERE o.created_at >= '2026-09-30');

-- -----------------------------------------------------------------------------
-- Q2. EXISTS: the same question
-- -----------------------------------------------------------------------------

-- 1) The query itself
SELECT count(*)
FROM users u
WHERE EXISTS (SELECT 1 FROM orders o
              WHERE o.user_id = u.id AND o.created_at >= '2026-09-30');

-- 2) EXPLAIN: plan + ESTIMATES only. The query is NOT executed.
EXPLAIN
SELECT count(*)
FROM users u
WHERE EXISTS (SELECT 1 FROM orders o
              WHERE o.user_id = u.id AND o.created_at >= '2026-09-30');

-- 3) EXPLAIN ANALYZE: EXECUTES the query, adds actual time / rows / loops.
EXPLAIN ANALYZE
SELECT count(*)
FROM users u
WHERE EXISTS (SELECT 1 FROM orders o
              WHERE o.user_id = u.id AND o.created_at >= '2026-09-30');

-- 4) Full detail: buffers (I/O), output columns, non-default settings.
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS)
SELECT count(*)
FROM users u
WHERE EXISTS (SELECT 1 FROM orders o
              WHERE o.user_id = u.id AND o.created_at >= '2026-09-30');

-- Observe:
--   * Same Semi Join plan as IN: for positive membership both are equivalent

-- -----------------------------------------------------------------------------
-- Q3. NOT EXISTS: recent sign-ups who never ordered
-- -----------------------------------------------------------------------------

-- 1) The query itself
SELECT count(*)
FROM users u
WHERE u.created_at >= '2026-09-25'
  AND NOT EXISTS (SELECT 1 FROM orders o WHERE o.user_id = u.id);

-- 2) EXPLAIN: plan + ESTIMATES only. The query is NOT executed.
EXPLAIN
SELECT count(*)
FROM users u
WHERE u.created_at >= '2026-09-25'
  AND NOT EXISTS (SELECT 1 FROM orders o WHERE o.user_id = u.id);

-- 3) EXPLAIN ANALYZE: EXECUTES the query, adds actual time / rows / loops.
EXPLAIN ANALYZE
SELECT count(*)
FROM users u
WHERE u.created_at >= '2026-09-25'
  AND NOT EXISTS (SELECT 1 FROM orders o WHERE o.user_id = u.id);

-- 4) Full detail: buffers (I/O), output columns, non-default settings.
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS)
SELECT count(*)
FROM users u
WHERE u.created_at >= '2026-09-25'
  AND NOT EXISTS (SELECT 1 FROM orders o WHERE o.user_id = u.id);

-- Observe:
--   * Anti Join (Nested Loop Anti Join with an index lookup per user)

-- -----------------------------------------------------------------------------
-- Q4. NOT IN: the same question - EXPLAIN ONLY
-- -----------------------------------------------------------------------------

-- !!! EXPLAIN ONLY. Do NOT run this query or EXPLAIN ANALYZE it: the plan below
-- !!! is the reason (it could run for hours). Plain EXPLAIN does not execute it.
EXPLAIN
SELECT count(*)
FROM users u
WHERE u.created_at >= '2026-09-25'
  AND u.id NOT IN (SELECT o.user_id FROM orders o);

-- Observe:
--   * NOT (SubPlan 1) over a Materialize of ALL order user_ids: the 5M ids do not fit in
--   * work_mem as a hash, so the subplan is a plain (non-hashed) one, rescanned for every
--   * user -> O(users x orders). That is why this query is only EXPLAINed.

-- Observe in every plan:
--   * Scan / join type of every node (Seq Scan, Index Scan, Bitmap Heap Scan, Hash Join ...)
--   * cost=startup..total  (planner units, NOT milliseconds)
--   * rows= estimated  vs  actual rows=  (x loops)  -> how wrong is the estimate?
--   * Rows Removed by Filter: rows read and thrown away
--   * Buffers: shared hit (already in shared_buffers) / read (fetched from OS cache or disk)
--   * Planning Time / Execution Time (run 5-10 times, keep the typical value)

-- Record the numbers in 04_compare.sql, then run 02_optimize.sql.
