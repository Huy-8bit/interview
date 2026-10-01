-- =============================================================================
-- Challenge 04 · What must warehouse 3 restock first?
-- Topic: Partial index with an expression predicate   Tables: inventory
-- Run on PRIMARY (localhost:5432). Solution: solutions/solution_04.sql (try first!)
-- =============================================================================

-- BUSINESS REQUIREMENT
-- Warehouse 3 manager: the 50 products with the lowest available stock among those at or below
-- their reorder level.

-- YOUR TASK
--   1. Run the EXPLAIN statements below and find the bottleneck.
--   2. Propose an optimization (index, rewrite, statistics...) and measure it.
--   3. Write down the trade-offs (size, write cost, freshness...).
--   4. Undo what you created (DROP ...). Check: ../00_environment/09_verify_baseline.sql

-- HINT (read only if stuck)
-- idx_inventory_needs_restock already has the right predicate. What does it lack for this query?

-- THE SLOW QUERY
SELECT product_id, quantity, reserved_quantity, reorder_level
FROM inventory
WHERE warehouse_id = 3
  AND quantity - reserved_quantity <= reorder_level
ORDER BY quantity - reserved_quantity
LIMIT 50;

EXPLAIN
SELECT product_id, quantity, reserved_quantity, reorder_level
FROM inventory
WHERE warehouse_id = 3
  AND quantity - reserved_quantity <= reorder_level
ORDER BY quantity - reserved_quantity
LIMIT 50;

EXPLAIN (ANALYZE, BUFFERS)
SELECT product_id, quantity, reserved_quantity, reorder_level
FROM inventory
WHERE warehouse_id = 3
  AND quantity - reserved_quantity <= reorder_level
ORDER BY quantity - reserved_quantity
LIMIT 50;

