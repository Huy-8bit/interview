-- =============================================================================
-- Challenge 03 · Yearly revenue per payment method
-- Topic: Sargable rewrite   Tables: payments
-- Run on PRIMARY (localhost:5432). Solution: solutions/solution_03.sql (try first!)
-- =============================================================================

-- BUSINESS REQUIREMENT
-- Finance report: number and amount of SUCCEEDED payments per method for the year 2025.

-- YOUR TASK
--   1. Run the EXPLAIN statements below and find the bottleneck.
--   2. Propose an optimization (index, rewrite, statistics...) and measure it.
--   3. Write down the trade-offs (size, write cost, freshness...).
--   4. Undo what you created (DROP ...). Check: ../00_environment/09_verify_baseline.sql

-- HINT (read only if stuck)
-- Look at the estimated rows of the scan. What does the planner know about date_trunc(...)?

-- THE SLOW QUERY
EXPLAIN
SELECT payment_method, count(*), sum(amount)
FROM payments
WHERE status = 'SUCCEEDED'
  AND date_trunc('year', created_at) = '2025-01-01'
GROUP BY payment_method;

EXPLAIN (ANALYZE, BUFFERS)
SELECT payment_method, count(*), sum(amount)
FROM payments
WHERE status = 'SUCCEEDED'
  AND date_trunc('year', created_at) = '2025-01-01'
GROUP BY payment_method;

