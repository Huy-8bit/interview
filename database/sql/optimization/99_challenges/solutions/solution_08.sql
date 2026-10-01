-- =============================================================================
-- Solution 08 · Pink products of a category
-- Ends with a reset: the database is back at its baseline.
-- =============================================================================

-- WHY THE ORIGINAL IS SLOW / WHAT CHANGES
-- idx_products_attributes_gin (jsonb_path_ops) only supports @> (containment). Written with
-- ->> the condition can only be a Filter. Written as attributes @> '{"color": "Pink"}' the
-- planner can combine the GIN bitmap with the category index (BitmapAnd). No DDL needed.

-- 2) The rewritten query
EXPLAIN (ANALYZE, BUFFERS)
SELECT id, name, price
FROM products
WHERE category_id = 12
  AND status = 'ACTIVE'
  AND attributes @> '{"color": "Pink"}';

-- 3) Reset
-- no objects created
RESET ALL;

