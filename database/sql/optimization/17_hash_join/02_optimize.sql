-- =============================================================================
-- Lab 17 · Hash Join: build the small side, probe with the big side — OPTIMIZE · Strategy A
-- Strategy A: (experiment) work_mem = 1MB: the hash table spills to disk (Batches > 1)
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

-- What / why:
-- A hash table may use work_mem x hash_mem_multiplier (x workers for a parallel
-- hash). If the build side does not fit, it is split into batches written to
-- temporary files: Batches > 1 and 'temp read/written' in Buffers.

-- -----------------------------------------------------------------------------
-- Same query, work_mem = 1MB
-- -----------------------------------------------------------------------------

-- Session setting for this query (undone by the RESET below):
SET work_mem = '1MB';

-- 1) The query itself
SELECT p.payment_method, o.status, count(*) AS payments, sum(p.amount) AS amount
FROM payments p
JOIN orders o ON o.id = p.order_id
WHERE o.created_at >= '2026-09-01'
GROUP BY p.payment_method, o.status
ORDER BY p.payment_method, o.status;

-- 2) EXPLAIN: plan + ESTIMATES only. The query is NOT executed.
EXPLAIN
SELECT p.payment_method, o.status, count(*) AS payments, sum(p.amount) AS amount
FROM payments p
JOIN orders o ON o.id = p.order_id
WHERE o.created_at >= '2026-09-01'
GROUP BY p.payment_method, o.status
ORDER BY p.payment_method, o.status;

-- 3) EXPLAIN ANALYZE: EXECUTES the query, adds actual time / rows / loops.
EXPLAIN ANALYZE
SELECT p.payment_method, o.status, count(*) AS payments, sum(p.amount) AS amount
FROM payments p
JOIN orders o ON o.id = p.order_id
WHERE o.created_at >= '2026-09-01'
GROUP BY p.payment_method, o.status
ORDER BY p.payment_method, o.status;

-- 4) Full detail: buffers (I/O), output columns, non-default settings.
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS)
SELECT p.payment_method, o.status, count(*) AS payments, sum(p.amount) AS amount
FROM payments p
JOIN orders o ON o.id = p.order_id
WHERE o.created_at >= '2026-09-01'
GROUP BY p.payment_method, o.status
ORDER BY p.payment_method, o.status;

RESET work_mem;

-- Observe:
--   * Batches: N (N > 1), Buffers: temp read=... written=...

-- Undo only this strategy:
-- RESET work_mem;

-- Next: run 05_reset.sql, compare with 01_before.sql, then 05_reset.sql.
