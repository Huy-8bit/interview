-- =============================================================================
-- Solution 14 · Categories with the most 5-star reviews this quarter
-- Ends with a reset: the database is back at its baseline.
-- =============================================================================

-- WHY THE ORIGINAL IS SLOW / WHAT CHANGES
-- Two bottlenecks, found one after the other:
-- 1. reviews has no index on created_at: all 5M reviews are scanned to keep ~770k recent 5-star
--    ones. A partial index (created_at) INCLUDE (product_id) WHERE rating = 5 turns that into an
--    Index Only Scan (~300 ms -> ~30 ms) - but the total barely moves, because:
-- 2. the ~770k rows then look up products (Nested Loop + Memoize over pk_products) in a 2 GB heap
--    of wide rows just to read category_id. A covering index products (id) INCLUDE (category_id)
--    makes that lookup an Index Only Scan as well (same technique as Lab 20).
-- Lesson: fix the biggest node, re-measure, the next bottleneck appears.

-- 1) Optimization
CREATE INDEX ix_lab99_c14_five_star ON reviews (created_at) INCLUDE (product_id) WHERE rating = 5;
VACUUM (ANALYZE) reviews;
-- measure here (EXPLAIN (ANALYZE, BUFFERS) of the query): the reviews scan is fast now, the
-- products lookup dominates. Second step:
CREATE INDEX ix_lab99_c14_products_category ON products (id) INCLUDE (category_id);
VACUUM (ANALYZE) products;

-- 2) The same query, after the optimization
EXPLAIN (ANALYZE, BUFFERS)
SELECT c.name, count(*) AS five_star_reviews
FROM reviews r
JOIN products p   ON p.id = r.product_id
JOIN categories c ON c.id = p.category_id
WHERE r.rating = 5 AND r.created_at >= '2026-07-01'
GROUP BY c.name
ORDER BY five_star_reviews DESC
LIMIT 10;

-- 3) Reset
DROP INDEX IF EXISTS ix_lab99_c14_five_star;
DROP INDEX IF EXISTS ix_lab99_c14_products_category;
RESET ALL;

ANALYZE reviews;
SELECT count(*) AS lab99_indexes_left FROM pg_indexes WHERE indexname LIKE 'ix\_lab99\_c14%';   -- 0

