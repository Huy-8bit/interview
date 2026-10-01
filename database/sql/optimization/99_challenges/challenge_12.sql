-- =============================================================================
-- Challenge 12 · Customers living in Da Nang
-- Topic: Partial index   Tables: users, addresses
-- Run on PRIMARY (localhost:5432). Solution: solutions/solution_12.sql (try first!)
-- =============================================================================

-- BUSINESS REQUIREMENT
-- Local promotion: usernames of customers whose DEFAULT address is in Da Nang.

-- YOUR TASK
--   1. Run the EXPLAIN statements below and find the bottleneck.
--   2. Propose an optimization (index, rewrite, statistics...) and measure it.
--   3. Write down the trade-offs (size, write cost, freshness...).
--   4. Undo what you created (DROP ...). Check: ../00_environment/09_verify_baseline.sql

-- HINT (read only if stuck)
-- Which index could find the Da Nang default addresses without reading 8M addresses?

-- THE SLOW QUERY
EXPLAIN
SELECT u.id, u.username
FROM addresses a
JOIN users u ON u.id = a.user_id
WHERE a.city = 'Da Nang' AND a.is_default;

EXPLAIN (ANALYZE, BUFFERS)
SELECT u.id, u.username
FROM addresses a
JOIN users u ON u.id = a.user_id
WHERE a.city = 'Da Nang' AND a.is_default;

