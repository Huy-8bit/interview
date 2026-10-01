-- =============================================================================
-- Solution 05 · Negative reviews of the best seller
-- Ends with a reset: the database is back at its baseline.
-- =============================================================================

-- WHY THE ORIGINAL IS SLOW / WHAT CHANGES
-- idx_reviews_product_id fetches all ~17k reviews of the product from the heap, filters rating,
-- then sorts. A partial index (product_id, created_at DESC) WHERE rating <= 2 contains only
-- negative reviews already in the requested order: the LIMIT stops after 20 entries.

-- 1) Optimization
CREATE INDEX ix_lab99_c05_reviews_negative ON reviews (product_id, created_at DESC) WHERE rating <= 2;

-- 2) The same query, after the optimization
EXPLAIN (ANALYZE, BUFFERS)
SELECT id, user_id, rating, title, created_at
FROM reviews
WHERE product_id = 1986295 AND rating <= 2
ORDER BY created_at DESC
LIMIT 20;

-- 3) Reset
DROP INDEX IF EXISTS ix_lab99_c05_reviews_negative;
RESET ALL;

ANALYZE reviews;
SELECT count(*) AS lab99_indexes_left FROM pg_indexes WHERE indexname LIKE 'ix\_lab99\_c05%';   -- 0

