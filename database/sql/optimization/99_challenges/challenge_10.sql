-- =============================================================================
-- Challenge 10 · Daily active buyers in September
-- Topic: Index Only Scan + aggregation   Tables: orders
-- Run on PRIMARY (localhost:5432). Solution: solutions/solution_10.sql (try first!)
-- =============================================================================

-- BUSINESS REQUIREMENT
-- Growth dashboard: number of distinct buyers per day in September 2026.

-- YOUR TASK
--   1. Run the EXPLAIN statements below and find the bottleneck.
--   2. Propose an optimization (index, rewrite, statistics...) and measure it.
--   3. Write down the trade-offs (size, write cost, freshness...).
--   4. Undo what you created (DROP ...). Check: ../00_environment/09_verify_baseline.sql

-- HINT (read only if stuck)
-- The range is already sargable. Which columns does the query read from the heap, and how many heap pages is that?

-- THE SLOW QUERY
EXPLAIN
SELECT created_at::date AS day, count(DISTINCT user_id) AS buyers
FROM orders
WHERE created_at >= '2026-09-01' AND created_at < '2026-10-01'
GROUP BY created_at::date
ORDER BY day;

EXPLAIN (ANALYZE, BUFFERS)
SELECT created_at::date AS day, count(DISTINCT user_id) AS buyers
FROM orders
WHERE created_at >= '2026-09-01' AND created_at < '2026-10-01'
GROUP BY created_at::date
ORDER BY day;

