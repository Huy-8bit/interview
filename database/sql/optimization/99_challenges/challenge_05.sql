-- =============================================================================
-- Challenge 05 · Negative reviews of the best seller
-- Topic: Index for filter + sort   Tables: reviews
-- Run on PRIMARY (localhost:5432). Solution: solutions/solution_05.sql (try first!)
-- =============================================================================

-- BUSINESS REQUIREMENT
-- Product page, 'critical reviews' tab: the 20 newest reviews with rating <= 2 of product 4905450.

-- YOUR TASK
--   1. Run the EXPLAIN statements below and find the bottleneck.
--   2. Propose an optimization (index, rewrite, statistics...) and measure it.
--   3. Write down the trade-offs (size, write cost, freshness...).
--   4. Undo what you created (DROP ...). Check: ../00_environment/09_verify_baseline.sql

-- HINT (read only if stuck)
-- How many reviews does the product have, how many are <= 2, and in which order are they read?

-- THE SLOW QUERY
SELECT id, user_id, rating, title, created_at
FROM reviews
WHERE product_id = 4905450 AND rating <= 2
ORDER BY created_at DESC
LIMIT 20;

EXPLAIN
SELECT id, user_id, rating, title, created_at
FROM reviews
WHERE product_id = 4905450 AND rating <= 2
ORDER BY created_at DESC
LIMIT 20;

EXPLAIN (ANALYZE, BUFFERS)
SELECT id, user_id, rating, title, created_at
FROM reviews
WHERE product_id = 4905450 AND rating <= 2
ORDER BY created_at DESC
LIMIT 20;

