-- =============================================================================
-- Challenge 08 · Pink products of a category
-- Topic: Use the existing index   Tables: products
-- Run on PRIMARY (localhost:5432). Solution: solutions/solution_08.sql (try first!)
-- =============================================================================

-- BUSINESS REQUIREMENT
-- Catalog filter: ACTIVE pink products of category 12.

-- YOUR TASK
--   1. Run the EXPLAIN statements below and find the bottleneck.
--   2. Propose an optimization (index, rewrite, statistics...) and measure it.
--   3. Write down the trade-offs (size, write cost, freshness...).
--   4. Undo what you created (DROP ...). Check: ../00_environment/09_verify_baseline.sql

-- HINT (read only if stuck)
-- There is already a GIN index on products.attributes. Which operator does it support?

-- THE SLOW QUERY
EXPLAIN
SELECT id, name, price
FROM products
WHERE category_id = 12
  AND status = 'ACTIVE'
  AND attributes ->> 'color' = 'Pink';

EXPLAIN (ANALYZE, BUFFERS)
SELECT id, name, price
FROM products
WHERE category_id = 12
  AND status = 'ACTIVE'
  AND attributes ->> 'color' = 'Pink';

