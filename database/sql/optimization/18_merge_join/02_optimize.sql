-- =============================================================================
-- Lab 18 · Merge Join: two inputs already sorted on the join key — OPTIMIZE · Strategy A
-- Strategy A: (experiment) SET enable_mergejoin = off
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

-- What / why:
-- Without the merge join the planner must hash one side AND sort the 5M-row
-- result for the ORDER BY. The merge join gets both for free from the indexes.

-- -----------------------------------------------------------------------------
-- Q1 with merge joins disabled
-- -----------------------------------------------------------------------------

-- Session setting for this query (undone by the RESET below):
SET enable_mergejoin = off;

-- 2) EXPLAIN: plan + ESTIMATES only. The query is NOT executed.
EXPLAIN
SELECT o.id, o.status, p.status AS payment_status, p.amount
FROM orders o
JOIN payments p ON p.order_id = o.id
ORDER BY o.id;

-- 3) EXPLAIN ANALYZE: EXECUTES the query, adds actual time / rows / loops.
EXPLAIN ANALYZE
SELECT o.id, o.status, p.status AS payment_status, p.amount
FROM orders o
JOIN payments p ON p.order_id = o.id
ORDER BY o.id;

-- 4) Full detail: buffers (I/O), output columns, non-default settings.
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS)
SELECT o.id, o.status, p.status AS payment_status, p.amount
FROM orders o
JOIN payments p ON p.order_id = o.id
ORDER BY o.id;

RESET enable_mergejoin;

-- Observe:
--   * Hash Join + Sort (external merge on disk?) - compare time and temp buffers

-- Undo only this strategy:
-- RESET enable_mergejoin;

-- Next: run 05_reset.sql, compare with 01_before.sql, then 05_reset.sql.
