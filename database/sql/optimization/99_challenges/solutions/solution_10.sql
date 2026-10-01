-- =============================================================================
-- Solution 10 · Daily active buyers in September
-- Ends with a reset: the database is back at its baseline.
-- =============================================================================

-- WHY THE ORIGINAL IS SLOW / WHAT CHANGES
-- The range uses idx_orders_created_at, but user_id is not in the index: 1.6M heap rows are read.
-- A covering index (created_at) INCLUDE (user_id) makes it an Index Only Scan - the rows arrive
-- in created_at order, so the per-day groups come out sorted too.

-- 1) Optimization
CREATE INDEX ix_lab99_c10_orders_created_user ON orders (created_at) INCLUDE (user_id);
VACUUM (ANALYZE) orders;

-- 2) The same query, after the optimization
EXPLAIN (ANALYZE, BUFFERS)
SELECT created_at::date AS day, count(DISTINCT user_id) AS buyers
FROM orders
WHERE created_at >= '2026-09-01' AND created_at < '2026-10-01'
GROUP BY created_at::date
ORDER BY day;

-- 3) Reset
DROP INDEX IF EXISTS ix_lab99_c10_orders_created_user;
RESET ALL;

ANALYZE orders;
SELECT count(*) AS lab99_indexes_left FROM pg_indexes WHERE indexname LIKE 'ix\_lab99\_c10%';   -- 0

