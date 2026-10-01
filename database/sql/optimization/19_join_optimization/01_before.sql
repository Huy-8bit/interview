-- =============================================================================
-- Lab 19 · Join optimization: the unindexed foreign key — BEFORE (baseline)
-- The query as it runs today, before any optimization.
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

-- Context: how big is the data this query touches?
-- reviews.order_id is a FOREIGN KEY without an index (deliberately, see 04-indexes.sql)
SELECT conname, pg_get_constraintdef(oid) FROM pg_constraint WHERE conname = 'fk_reviews_order';
SELECT count(*) AS reviews, count(order_id) AS with_order_id FROM reviews;

-- -----------------------------------------------------------------------------
-- Q1. Reviews of the orders placed on one day
-- -----------------------------------------------------------------------------

-- 1) The query itself
SELECT o.order_number, r.rating, r.title
FROM orders o
JOIN reviews r ON r.order_id = o.id
WHERE o.created_at >= '2025-06-01'
  AND o.created_at <  '2025-06-02';

-- 2) EXPLAIN: plan + ESTIMATES only. The query is NOT executed.
EXPLAIN
SELECT o.order_number, r.rating, r.title
FROM orders o
JOIN reviews r ON r.order_id = o.id
WHERE o.created_at >= '2025-06-01'
  AND o.created_at <  '2025-06-02';

-- 3) EXPLAIN ANALYZE: EXECUTES the query, adds actual time / rows / loops.
EXPLAIN ANALYZE
SELECT o.order_number, r.rating, r.title
FROM orders o
JOIN reviews r ON r.order_id = o.id
WHERE o.created_at >= '2025-06-01'
  AND o.created_at <  '2025-06-02';

-- 4) Full detail: buffers (I/O), output columns, non-default settings.
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS)
SELECT o.order_number, r.rating, r.title
FROM orders o
JOIN reviews r ON r.order_id = o.id
WHERE o.created_at >= '2025-06-01'
  AND o.created_at <  '2025-06-02';

-- Observe:
--   * Hash Join: hash the ~5k orders of that day, then Seq Scan ALL 5M reviews to probe it
--   * (the planner cannot look reviews up by order_id: no index)

-- -----------------------------------------------------------------------------
-- Q2. Delete one order (FK ON DELETE SET NULL must find its reviews)
-- -----------------------------------------------------------------------------

-- DML: EXPLAIN ANALYZE really EXECUTES the statement -> always inside a transaction
-- that is rolled back, so the lab data never changes.
BEGIN;

EXPLAIN
DELETE FROM orders WHERE id = 250001;

EXPLAIN (ANALYZE, BUFFERS, WAL, VERBOSE)
DELETE FROM orders WHERE id = 250001;

ROLLBACK;

-- Observe:
--   * Trigger for constraint fk_reviews_order: time=... calls=1  <- a hidden Seq Scan of reviews
--   * compare with fk_order_items_order / fk_payments_order (indexed: ~0.1 ms)

-- Observe in every plan:
--   * Scan / join type of every node (Seq Scan, Index Scan, Bitmap Heap Scan, Hash Join ...)
--   * cost=startup..total  (planner units, NOT milliseconds)
--   * rows= estimated  vs  actual rows=  (x loops)  -> how wrong is the estimate?
--   * Rows Removed by Filter: rows read and thrown away
--   * Buffers: shared hit (already in shared_buffers) / read (fetched from OS cache or disk)
--   * Planning Time / Execution Time (run 5-10 times, keep the typical value)

-- Record the numbers in 04_compare.sql, then run 02_optimize.sql.
