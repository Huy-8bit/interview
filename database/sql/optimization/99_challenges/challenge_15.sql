-- =============================================================================
-- Challenge 15 · A messy customer report
-- Topic: Query rewrite (everything together)   Tables: users, orders
-- Run on PRIMARY (localhost:5432). Solution: solutions/solution_15.sql (try first!)
-- =============================================================================

-- BUSINESS REQUIREMENT
-- Account managers: customers 3,000,000..3,050,000 with at least 2 COMPLETED orders in 2026,
-- with their number of such orders, total spent and last order date.

-- YOUR TASK
--   1. Run the EXPLAIN statements below and find the bottleneck.
--   2. Propose an optimization (index, rewrite, statistics...) and measure it.
--   3. Write down the trade-offs (size, write cost, freshness...).
--   4. Undo what you created (DROP ...). Check: ../00_environment/09_verify_baseline.sql

-- HINT (read only if stuck)
-- Count the anti-patterns: a JOIN that multiplies rows, DISTINCT to undo it, four correlated subqueries doing the same lookup.

-- THE SLOW QUERY
EXPLAIN
SELECT DISTINCT u.id, u.username,
       (SELECT count(*) FROM orders c
         WHERE c.user_id = u.id AND c.status = 'COMPLETED' AND c.created_at >= '2026-01-01') AS orders,
       (SELECT sum(c.total_amount) FROM orders c
         WHERE c.user_id = u.id AND c.status = 'COMPLETED' AND c.created_at >= '2026-01-01') AS spent,
       (SELECT max(c.created_at) FROM orders c
         WHERE c.user_id = u.id AND c.status = 'COMPLETED' AND c.created_at >= '2026-01-01') AS last_order
FROM users u
JOIN orders o ON o.user_id = u.id AND o.status = 'COMPLETED' AND o.created_at >= '2026-01-01'
WHERE u.id BETWEEN 3000000 AND 3050000
  AND (SELECT count(*) FROM orders c2
        WHERE c2.user_id = u.id AND c2.status = 'COMPLETED' AND c2.created_at >= '2026-01-01') >= 2;

EXPLAIN (ANALYZE, BUFFERS)
SELECT DISTINCT u.id, u.username,
       (SELECT count(*) FROM orders c
         WHERE c.user_id = u.id AND c.status = 'COMPLETED' AND c.created_at >= '2026-01-01') AS orders,
       (SELECT sum(c.total_amount) FROM orders c
         WHERE c.user_id = u.id AND c.status = 'COMPLETED' AND c.created_at >= '2026-01-01') AS spent,
       (SELECT max(c.created_at) FROM orders c
         WHERE c.user_id = u.id AND c.status = 'COMPLETED' AND c.created_at >= '2026-01-01') AS last_order
FROM users u
JOIN orders o ON o.user_id = u.id AND o.status = 'COMPLETED' AND o.created_at >= '2026-01-01'
WHERE u.id BETWEEN 3000000 AND 3050000
  AND (SELECT count(*) FROM orders c2
        WHERE c2.user_id = u.id AND c2.status = 'COMPLETED' AND c2.created_at >= '2026-01-01') >= 2;

