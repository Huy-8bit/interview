-- =============================================================================
-- Lab 17 · Hash Join: build the small side, probe with the big side — AFTER
-- The baseline query again (the strategies of this lab are experiments, not changes).
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Payments of September's orders, by method and order status
-- -----------------------------------------------------------------------------

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

-- Observe:
--   * Parallel Hash: the inner (build) side = the September orders (index range scan)
--   * Parallel Hash Join probes it with every payment row (Seq Scan on payments)
--   * Hash node: Buckets / Batches / Memory Usage. Batches: 1 = the hash table fits in memory

-- Record the numbers in 04_compare.sql, then run 05_reset.sql.
