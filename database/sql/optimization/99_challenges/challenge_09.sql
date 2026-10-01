-- =============================================================================
-- Challenge 09 · Page 200 of a product's reviews
-- Topic: Pagination   Tables: reviews
-- Run on PRIMARY (localhost:5432). Solution: solutions/solution_09.sql (try first!)
-- =============================================================================

-- BUSINESS REQUIREMENT
-- Product page lists reviews newest first, 20 per page. Page 200 (OFFSET 3980) is slow.

-- YOUR TASK
--   1. Run the EXPLAIN statements below and find the bottleneck.
--   2. Propose an optimization (index, rewrite, statistics...) and measure it.
--   3. Write down the trade-offs (size, write cost, freshness...).
--   4. Undo what you created (DROP ...). Check: ../00_environment/09_verify_baseline.sql

-- HINT (read only if stuck)
-- What does OFFSET force PostgreSQL to read? What would the 'next page' query look like with a cursor?

-- THE SLOW QUERY
SELECT id, user_id, rating, title, created_at
FROM reviews
WHERE product_id = 1986295
ORDER BY created_at DESC, id DESC
LIMIT 20 OFFSET 3980;

EXPLAIN
SELECT id, user_id, rating, title, created_at
FROM reviews
WHERE product_id = 1986295
ORDER BY created_at DESC, id DESC
LIMIT 20 OFFSET 3980;

EXPLAIN (ANALYZE, BUFFERS)
SELECT id, user_id, rating, title, created_at
FROM reviews
WHERE product_id = 1986295
ORDER BY created_at DESC, id DESC
LIMIT 20 OFFSET 3980;

