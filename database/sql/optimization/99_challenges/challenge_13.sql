-- =============================================================================
-- Challenge 13 · Find a payment by its transaction id
-- Topic: Implicit cast   Tables: payments
-- Run on PRIMARY (localhost:5432). Solution: solutions/solution_13.sql (try first!)
-- =============================================================================

-- BUSINESS REQUIREMENT
-- Support tool: look up a payment by the transaction id pasted from the provider's dashboard.

-- YOUR TASK
--   1. Run the EXPLAIN statements below and find the bottleneck.
--   2. Propose an optimization (index, rewrite, statistics...) and measure it.
--   3. Write down the trade-offs (size, write cost, freshness...).
--   4. Undo what you created (DROP ...). Check: ../00_environment/09_verify_baseline.sql

-- HINT (read only if stuck)
-- transaction_id is a uuid with a UNIQUE index. Look at the Filter line.

-- THE SLOW QUERY
EXPLAIN
SELECT id, order_id, amount, status
FROM payments
WHERE transaction_id::text = 'cba2d687-53f9-4f79-93c3-3ae06278f1c1';

EXPLAIN (ANALYZE, BUFFERS)
SELECT id, order_id, amount, status
FROM payments
WHERE transaction_id::text = 'cba2d687-53f9-4f79-93c3-3ae06278f1c1';

