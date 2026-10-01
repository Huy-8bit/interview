-- =============================================================================
-- Solution 11 · Order lookup by order number (case-insensitive input)
-- Ends with a reset: the database is back at its baseline.
-- =============================================================================

-- WHY THE ORIGINAL IS SLOW / WHAT CHANGES
-- upper() on the column disables uq_orders_order_number (Seq Scan of 5M orders). All stored
-- values are already upper case, so normalize the INPUT instead: order_number = upper($1).
-- No DDL needed (an expression index on upper(order_number) would also work, but costs a second
-- index for nothing).

-- 2) The rewritten query
EXPLAIN (ANALYZE, BUFFERS)
SELECT o.order_number, o.status, p.name, i.quantity, i.total_price
FROM orders o
JOIN order_items i ON i.order_id = o.id
JOIN products p    ON p.id = i.product_id
WHERE o.order_number = upper('ord-241217-00250000');

-- 3) Reset
-- no objects created
RESET ALL;

