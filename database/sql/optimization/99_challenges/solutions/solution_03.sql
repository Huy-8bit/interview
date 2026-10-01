-- =============================================================================
-- Solution 03 · Yearly revenue per payment method
-- Ends with a reset: the database is back at its baseline.
-- =============================================================================

-- WHY THE ORIGINAL IS SLOW / WHAT CHANGES
-- date_trunc() on the column hides it from statistics (and from any index): the planner guesses
-- 0.5% of the rows. Rewritten as a half-open range the estimate comes from the created_at
-- histogram. An index on (created_at) INCLUDE (status, payment_method, amount) then lets the
-- report read only 2025 as an Index Only Scan instead of the whole table.

-- 1) Optimization
CREATE INDEX ix_lab99_c03_payments_created ON payments (created_at) INCLUDE (status, payment_method, amount);
VACUUM (ANALYZE) payments;

-- 2) The rewritten query
EXPLAIN (ANALYZE, BUFFERS)
SELECT payment_method, count(*), sum(amount)
FROM payments
WHERE status = 'SUCCEEDED'
  AND created_at >= '2025-01-01' AND created_at < '2026-01-01'
GROUP BY payment_method;

-- (the original query with the new index, for comparison)
EXPLAIN (ANALYZE, BUFFERS)
SELECT payment_method, count(*), sum(amount)
FROM payments
WHERE status = 'SUCCEEDED'
  AND date_trunc('year', created_at) = '2025-01-01'
GROUP BY payment_method;

-- 3) Reset
DROP INDEX IF EXISTS ix_lab99_c03_payments_created;
RESET ALL;

ANALYZE payments;
SELECT count(*) AS lab99_indexes_left FROM pg_indexes WHERE indexname LIKE 'ix\_lab99\_c03%';   -- 0

