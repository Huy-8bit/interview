-- =============================================================================
-- Solution 04 · What must warehouse 3 restock first?
-- Ends with a reset: the database is back at its baseline.
-- =============================================================================

-- WHY THE ORIGINAL IS SLOW / WHAT CHANGES
-- The existing partial index idx_inventory_needs_restock (product_id) WHERE ... has the right
-- predicate but neither warehouse_id nor the sort expression: the planner reads every
-- restock row of every warehouse and sorts. A partial index on (warehouse_id, (quantity -
-- reserved_quantity)) with the same predicate returns the 50 rows of warehouse 3 in order.

-- 1) Optimization
CREATE INDEX ix_lab99_c04_restock_by_wh ON inventory (warehouse_id, (quantity - reserved_quantity))
    WHERE quantity - reserved_quantity <= reorder_level;

-- 2) The same query, after the optimization
EXPLAIN (ANALYZE, BUFFERS)
SELECT product_id, quantity, reserved_quantity, reorder_level
FROM inventory
WHERE warehouse_id = 3
  AND quantity - reserved_quantity <= reorder_level
ORDER BY quantity - reserved_quantity
LIMIT 50;

-- 3) Reset
DROP INDEX IF EXISTS ix_lab99_c04_restock_by_wh;
RESET ALL;

ANALYZE inventory;
SELECT count(*) AS lab99_indexes_left FROM pg_indexes WHERE indexname LIKE 'ix\_lab99\_c04%';   -- 0

