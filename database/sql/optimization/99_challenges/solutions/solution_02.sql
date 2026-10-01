-- =============================================================================
-- Solution 02 · Latest orders that used a coupon
-- Ends with a reset: the database is back at its baseline.
-- =============================================================================

-- WHY THE ORIGINAL IS SLOW / WHAT CHANGES
-- The planner walks idx_orders_status_created_at (or idx_orders_created_at) backwards and
-- filters coupon_code row by row. An index ordered by (coupon_code, status, created_at DESC)
-- returns exactly the 20 rows. Making it partial (WHERE coupon_code IS NOT NULL) keeps only the
-- ~12% of orders that have a coupon: much smaller, cheaper to maintain.

-- 1) Optimization
CREATE INDEX ix_lab99_c02_orders_coupon ON orders (coupon_code, status, created_at DESC)
    WHERE coupon_code IS NOT NULL;

-- 2) The same query, after the optimization
EXPLAIN (ANALYZE, BUFFERS)
SELECT id, order_number, user_id, total_amount, created_at
FROM orders
WHERE coupon_code = 'VIP20' AND status = 'COMPLETED'
ORDER BY created_at DESC
LIMIT 20;

-- 3) Reset
DROP INDEX IF EXISTS ix_lab99_c02_orders_coupon;
RESET ALL;

ANALYZE orders;
SELECT count(*) AS lab99_indexes_left FROM pg_indexes WHERE indexname LIKE 'ix\_lab99\_c02%';   -- 0

