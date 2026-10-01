-- =============================================================================
-- Challenge 06 · Top 10 spenders of 2026
-- Topic: Aggregation   Tables: orders
-- Run on PRIMARY (localhost:5432). Solution: solutions/solution_06.sql (try first!)
-- =============================================================================

-- BUSINESS REQUIREMENT
-- Loyalty program: the 10 customers with the highest total of COMPLETED orders in 2026.

-- YOUR TASK
--   1. Run the EXPLAIN statements below and find the bottleneck.
--   2. Propose an optimization (index, rewrite, statistics...) and measure it.
--   3. Write down the trade-offs (size, write cost, freshness...).
--   4. Undo what you created (DROP ...). Check: ../00_environment/09_verify_baseline.sql

-- HINT (read only if stuck)
-- Look at the aggregate node: Batches? Disk Usage? Which input order would avoid hashing millions of groups?

-- THE SLOW QUERY
SELECT user_id, sum(total_amount) AS spent
FROM orders
WHERE status = 'COMPLETED'
  AND created_at >= '2026-01-01'
GROUP BY user_id
ORDER BY spent DESC
LIMIT 10;

EXPLAIN
SELECT user_id, sum(total_amount) AS spent
FROM orders
WHERE status = 'COMPLETED'
  AND created_at >= '2026-01-01'
GROUP BY user_id
ORDER BY spent DESC
LIMIT 10;

EXPLAIN (ANALYZE, BUFFERS)
SELECT user_id, sum(total_amount) AS spent
FROM orders
WHERE status = 'COMPLETED'
  AND created_at >= '2026-01-01'
GROUP BY user_id
ORDER BY spent DESC
LIMIT 10;

