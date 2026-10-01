-- =============================================================================
-- Solution 07 · Loyal customers who never write reviews
-- Ends with a reset: the database is back at its baseline.
-- =============================================================================

-- WHY THE ORIGINAL IS SLOW / WHAT CHANGES
-- Two scalar subqueries run once PER USER (500,000 x 2 index lookups). Step 1 - rewrite: compute
-- 'users with >= 3 completed orders' once with GROUP BY ... HAVING, then 'no review' with NOT
-- EXISTS (anti join on uq_reviews_user_product, leading column user_id).
-- Measured: the rewrite alone is NOT faster - both versions spend their time reading ~375k
-- random heap pages of orders just to check status = 'COMPLETED' (orders are stored by date,
-- user_id is random). Step 2 - a partial index (user_id) WHERE status = 'COMPLETED': the status
-- test is answered by the index predicate, so the GROUP BY reads an Index Only Scan.

-- 1) Optimization
CREATE INDEX ix_lab99_c07_completed_by_user ON orders (user_id) WHERE status = 'COMPLETED';

-- 2) The rewritten query
EXPLAIN (ANALYZE, BUFFERS)
SELECT u.id, u.username
FROM (SELECT o.user_id
      FROM orders o
      WHERE o.user_id <= 500000 AND o.status = 'COMPLETED'
      GROUP BY o.user_id
      HAVING count(*) >= 3) loyal
JOIN users u ON u.id = loyal.user_id
WHERE NOT EXISTS (SELECT 1 FROM reviews r WHERE r.user_id = loyal.user_id);

-- (the original query with the new index, for comparison)
EXPLAIN (ANALYZE, BUFFERS)
SELECT u.id, u.username
FROM users u
WHERE u.id <= 500000
  AND (SELECT count(*) FROM orders o WHERE o.user_id = u.id AND o.status = 'COMPLETED') >= 3
  AND (SELECT count(*) FROM reviews r WHERE r.user_id = u.id) = 0;

-- 3) Reset
DROP INDEX IF EXISTS ix_lab99_c07_completed_by_user;
RESET ALL;

ANALYZE users;
SELECT count(*) AS lab99_indexes_left FROM pg_indexes WHERE indexname LIKE 'ix\_lab99\_c07%';   -- 0

