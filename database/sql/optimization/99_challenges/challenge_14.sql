-- =============================================================================
-- Challenge 14 · Categories with the most 5-star reviews this quarter
-- Topic: Join + covering partial index   Tables: reviews, products, categories
-- Run on PRIMARY (localhost:5432). Solution: solutions/solution_14.sql (try first!)
-- =============================================================================

-- BUSINESS REQUIREMENT
-- Merchandising: top 10 categories by number of 5-star reviews written since 2026-07-01.

-- YOUR TASK
--   1. Run the EXPLAIN statements below and find the bottleneck.
--   2. Propose an optimization (index, rewrite, statistics...) and measure it.
--   3. Write down the trade-offs (size, write cost, freshness...).
--   4. Undo what you created (DROP ...). Check: ../00_environment/09_verify_baseline.sql

-- HINT (read only if stuck)
-- Which table is scanned in full? Which columns of it are needed?

-- THE SLOW QUERY
SELECT c.name, count(*) AS five_star_reviews
FROM reviews r
JOIN products p   ON p.id = r.product_id
JOIN categories c ON c.id = p.category_id
WHERE r.rating = 5 AND r.created_at >= '2026-07-01'
GROUP BY c.name
ORDER BY five_star_reviews DESC
LIMIT 10;

EXPLAIN
SELECT c.name, count(*) AS five_star_reviews
FROM reviews r
JOIN products p   ON p.id = r.product_id
JOIN categories c ON c.id = p.category_id
WHERE r.rating = 5 AND r.created_at >= '2026-07-01'
GROUP BY c.name
ORDER BY five_star_reviews DESC
LIMIT 10;

EXPLAIN (ANALYZE, BUFFERS)
SELECT c.name, count(*) AS five_star_reviews
FROM reviews r
JOIN products p   ON p.id = r.product_id
JOIN categories c ON c.id = p.category_id
WHERE r.rating = 5 AND r.created_at >= '2026-07-01'
GROUP BY c.name
ORDER BY five_star_reviews DESC
LIMIT 10;

