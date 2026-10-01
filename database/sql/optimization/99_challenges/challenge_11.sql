-- =============================================================================
-- Challenge 11 · Order lookup by order number (case-insensitive input)
-- Topic: Function on an indexed column   Tables: orders, order_items, products
-- Run on PRIMARY (localhost:5432). Solution: solutions/solution_11.sql (try first!)
-- =============================================================================

-- BUSINESS REQUIREMENT
-- Order-detail API. Users may type the order number in lower case.

-- YOUR TASK
--   1. Run the EXPLAIN statements below and find the bottleneck.
--   2. Propose an optimization (index, rewrite, statistics...) and measure it.
--   3. Write down the trade-offs (size, write cost, freshness...).
--   4. Undo what you created (DROP ...). Check: ../00_environment/09_verify_baseline.sql

-- HINT (read only if stuck)
-- Order numbers are always stored in upper case. Where should upper() be applied?

-- THE SLOW QUERY
EXPLAIN
SELECT o.order_number, o.status, p.name, i.quantity, i.total_price
FROM orders o
JOIN order_items i ON i.order_id = o.id
JOIN products p    ON p.id = i.product_id
WHERE upper(o.order_number) = upper('ord-241218-00250000');

EXPLAIN (ANALYZE, BUFFERS)
SELECT o.order_number, o.status, p.name, i.quantity, i.total_price
FROM orders o
JOIN order_items i ON i.order_id = o.id
JOIN products p    ON p.id = i.product_id
WHERE upper(o.order_number) = upper('ord-241218-00250000');

