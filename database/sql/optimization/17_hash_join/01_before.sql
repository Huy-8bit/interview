-- =============================================================================
-- Lab 17 · Hash Join: build the small side, probe with the big side — BEFORE (baseline)
-- The query as it runs today, before any optimization.
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

-- Context: how big is the data this query touches?
SELECT count(*) AS orders_since_2026_09_01 FROM orders WHERE created_at >= '2026-09-01';

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

-- Observe in every plan:
--   * Scan / join type of every node (Seq Scan, Index Scan, Bitmap Heap Scan, Hash Join ...)
--   * cost=startup..total  (planner units, NOT milliseconds)
--   * rows= estimated  vs  actual rows=  (x loops)  -> how wrong is the estimate?
--   * Rows Removed by Filter: rows read and thrown away
--   * Buffers: shared hit (already in shared_buffers) / read (fetched from OS cache or disk)
--   * Planning Time / Execution Time (run 5-10 times, keep the typical value)

-- Record the numbers in 04_compare.sql, then run 02_optimize.sql.
