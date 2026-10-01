-- =============================================================================
-- Solution 12 · Customers living in Da Nang
-- Ends with a reset: the database is back at its baseline.
-- =============================================================================

-- WHY THE ORIGINAL IS SLOW / WHAT CHANGES
-- addresses.city has no index: Seq Scan of 8M addresses. Only default addresses are queried,
-- so a partial index (city) WHERE is_default indexes 5M rows instead of 8M.

-- 1) Optimization
CREATE INDEX ix_lab99_c12_default_city ON addresses (city) WHERE is_default;

-- 2) The same query, after the optimization
EXPLAIN (ANALYZE, BUFFERS)
SELECT u.id, u.username
FROM addresses a
JOIN users u ON u.id = a.user_id
WHERE a.city = 'Da Nang' AND a.is_default;

-- 3) Reset
DROP INDEX IF EXISTS ix_lab99_c12_default_city;
RESET ALL;

ANALYZE users;
SELECT count(*) AS lab99_indexes_left FROM pg_indexes WHERE indexname LIKE 'ix\_lab99\_c12%';   -- 0

