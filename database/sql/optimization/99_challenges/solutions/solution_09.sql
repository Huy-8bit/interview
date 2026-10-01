-- =============================================================================
-- Solution 09 · Page 200 of a product's reviews
-- Ends with a reset: the database is back at its baseline.
-- =============================================================================

-- WHY THE ORIGINAL IS SLOW / WHAT CHANGES
-- The plan fetches every review of the product, sorts them, and discards 3,980 rows. Two fixes
-- together: an index on (product_id, created_at DESC, id DESC) delivers the rows already sorted,
-- and keyset pagination ('the 20 rows after the last one of the previous page') reads only 20
-- entries whatever the page number. The cursor below is the (created_at, id) of the last row of
-- page 199 - in an application it comes from the previous response.

-- 1) Optimization
CREATE INDEX ix_lab99_c09_reviews_product_time ON reviews (product_id, created_at DESC, id DESC);

-- 2) The rewritten query
EXPLAIN (ANALYZE, BUFFERS)
SELECT id, user_id, rating, title, created_at
FROM reviews
WHERE product_id = 4905450
  AND (created_at, id) < (SELECT created_at, id FROM reviews WHERE product_id = 4905450
                          ORDER BY created_at DESC, id DESC OFFSET 3979 LIMIT 1)
ORDER BY created_at DESC, id DESC
LIMIT 20;

-- (the original query with the new index, for comparison)
EXPLAIN (ANALYZE, BUFFERS)
SELECT id, user_id, rating, title, created_at
FROM reviews
WHERE product_id = 4905450
ORDER BY created_at DESC, id DESC
LIMIT 20 OFFSET 3980;

-- 3) Reset
DROP INDEX IF EXISTS ix_lab99_c09_reviews_product_time;
RESET ALL;

ANALYZE reviews;
SELECT count(*) AS lab99_indexes_left FROM pg_indexes WHERE indexname LIKE 'ix\_lab99\_c09%';   -- 0

