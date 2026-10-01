-- =============================================================================
-- Challenge 01 · Find a customer by the last digits of the phone number
-- Topic: Index design   Tables: users
-- Run on PRIMARY (localhost:5432). Solution: solutions/solution_01.sql (try first!)
-- =============================================================================

-- BUSINESS REQUIREMENT
-- Call-center agents type the LAST 8 characters of a phone number ('523-1035') to find the caller.
-- Must answer in a few milliseconds.

-- YOUR TASK
--   1. Run the EXPLAIN statements below and find the bottleneck.
--   2. Propose an optimization (index, rewrite, statistics...) and measure it.
--   3. Write down the trade-offs (size, write cost, freshness...).
--   4. Undo what you created (DROP ...). Check: ../00_environment/09_verify_baseline.sql

-- HINT (read only if stuck)
-- A B-tree can only search a PREFIX. Can you turn a suffix search into a prefix search?

-- THE SLOW QUERY
EXPLAIN
SELECT id, username, phone FROM users WHERE phone LIKE '%523-1035';

EXPLAIN (ANALYZE, BUFFERS)
SELECT id, username, phone FROM users WHERE phone LIKE '%523-1035';

