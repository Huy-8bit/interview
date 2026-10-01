-- =============================================================================
-- Challenge 02 · Latest orders that used a coupon
-- Topic: Composite / partial index   Tables: orders
-- Run on PRIMARY (localhost:5432). Solution: solutions/solution_02.sql (try first!)
-- =============================================================================

-- BUSINESS REQUIREMENT
-- Marketing dashboard: the 20 most recent COMPLETED orders that used coupon 'VIP20'.
-- Coupons are used on ~12% of orders.

-- YOUR TASK
--   1. Run the EXPLAIN statements below and find the bottleneck.
--   2. Propose an optimization (index, rewrite, statistics...) and measure it.
--   3. Write down the trade-offs (size, write cost, freshness...).
--   4. Undo what you created (DROP ...). Check: ../00_environment/09_verify_baseline.sql

-- HINT (read only if stuck)
-- Equality columns first, ORDER BY column last. Do the 88% of orders without a coupon need to be in the index?

-- THE SLOW QUERY
SELECT id, order_number, user_id, total_amount, created_at
FROM orders
WHERE coupon_code = 'VIP20' AND status = 'COMPLETED'
ORDER BY created_at DESC
LIMIT 20;

EXPLAIN
SELECT id, order_number, user_id, total_amount, created_at
FROM orders
WHERE coupon_code = 'VIP20' AND status = 'COMPLETED'
ORDER BY created_at DESC
LIMIT 20;

EXPLAIN (ANALYZE, BUFFERS)
SELECT id, order_number, user_id, total_amount, created_at
FROM orders
WHERE coupon_code = 'VIP20' AND status = 'COMPLETED'
ORDER BY created_at DESC
LIMIT 20;

