-- =============================================================================
-- Challenge 07 · Loyal customers who never write reviews
-- Topic: Query rewrite   Tables: users, orders, reviews
-- Run on PRIMARY (localhost:5432). Solution: solutions/solution_07.sql (try first!)
-- =============================================================================

-- BUSINESS REQUIREMENT
-- CRM campaign: among customers 1..500,000, those with at least 3 COMPLETED orders who have never
-- written a review.

-- YOUR TASK
--   1. Run the EXPLAIN statements below and find the bottleneck.
--   2. Propose an optimization (index, rewrite, statistics...) and measure it.
--   3. Write down the trade-offs (size, write cost, freshness...).
--   4. Undo what you created (DROP ...). Check: ../00_environment/09_verify_baseline.sql

-- HINT (read only if stuck)
-- How many times does each SubPlan run (loops=)? Can the orders condition be computed once, grouped?

-- THE SLOW QUERY
EXPLAIN
SELECT u.id, u.username
FROM users u
WHERE u.id <= 500000
  AND (SELECT count(*) FROM orders o WHERE o.user_id = u.id AND o.status = 'COMPLETED') >= 3
  AND (SELECT count(*) FROM reviews r WHERE r.user_id = u.id) = 0;

EXPLAIN (ANALYZE, BUFFERS)
SELECT u.id, u.username
FROM users u
WHERE u.id <= 500000
  AND (SELECT count(*) FROM orders o WHERE o.user_id = u.id AND o.status = 'COMPLETED') >= 3
  AND (SELECT count(*) FROM reviews r WHERE r.user_id = u.id) = 0;

