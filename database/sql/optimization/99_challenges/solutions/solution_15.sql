-- =============================================================================
-- Solution 15 · A messy customer report
-- Ends with a reset: the database is back at its baseline.
-- =============================================================================

-- WHY THE ORIGINAL IS SLOW / WHAT CHANGES
-- The join produces one row per completed order, DISTINCT removes the duplicates again (a sort
-- of all of them), and four scalar subqueries repeat the same index lookup per output row
-- (SubPlan loops = thousands). One GROUP BY over the users' orders (served by
-- idx_orders_user_id) computes count, sum and max in a single pass, HAVING keeps the users with
-- >= 2 orders. No DDL needed.

-- 2) The rewritten query
EXPLAIN (ANALYZE, BUFFERS)
SELECT u.id, u.username, s.orders, s.spent, s.last_order
FROM (SELECT user_id, count(*) AS orders, sum(total_amount) AS spent, max(created_at) AS last_order
      FROM orders
      WHERE user_id BETWEEN 3000000 AND 3050000
        AND status = 'COMPLETED' AND created_at >= '2026-01-01'
      GROUP BY user_id
      HAVING count(*) >= 2) s
JOIN users u ON u.id = s.user_id;

-- 3) Reset
-- no objects created
RESET ALL;

