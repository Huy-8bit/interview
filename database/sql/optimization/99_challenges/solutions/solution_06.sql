-- =============================================================================
-- Solution 06 · Top 10 spenders of 2026
-- Ends with a reset: the database is back at its baseline.
-- =============================================================================

-- WHY THE ORIGINAL IS SLOW / WHAT CHANGES
-- Millions of groups make the HashAggregate spill to disk. A partial covering index ordered by
-- user_id (only COMPLETED orders, carrying created_at and total_amount) feeds a GroupAggregate
-- that streams one group at a time - no hash table, no spill. The ORDER BY spent still needs a
-- top-N sort, which is cheap.

-- 1) Optimization
CREATE INDEX ix_lab99_c06_completed_by_user ON orders (user_id) INCLUDE (created_at, total_amount)
    WHERE status = 'COMPLETED';
VACUUM (ANALYZE) orders;

-- 2) The same query, after the optimization
EXPLAIN (ANALYZE, BUFFERS)
SELECT user_id, sum(total_amount) AS spent
FROM orders
WHERE status = 'COMPLETED'
  AND created_at >= '2026-01-01'
GROUP BY user_id
ORDER BY spent DESC
LIMIT 10;

-- 3) Reset
DROP INDEX IF EXISTS ix_lab99_c06_completed_by_user;
RESET ALL;

ANALYZE orders;
SELECT count(*) AS lab99_indexes_left FROM pg_indexes WHERE indexname LIKE 'ix\_lab99\_c06%';   -- 0

