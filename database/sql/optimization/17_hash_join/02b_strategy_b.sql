-- =============================================================================
-- Lab 17 · Hash Join: build the small side, probe with the big side — OPTIMIZE · Strategy B
-- Strategy B: (experiment) SET enable_hashjoin = off: the alternative join
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

-- Start from the baseline: run 05_reset.sql first if another strategy is still applied.

-- What / why:
-- Shows what the planner would do without a hash join: a merge join needs
-- both inputs sorted by order_id (an index or an explicit Sort of millions of
-- rows); a nested loop needs one index lookup per row of the outer side.

-- -----------------------------------------------------------------------------
-- Same query with hash joins disabled
-- -----------------------------------------------------------------------------

-- Session setting for this query (undone by the RESET below):
SET enable_hashjoin = off;

-- 1) The query itself
SELECT p.payment_method, o.status, count(*) AS payments, sum(p.amount) AS amount
FROM payments p
JOIN orders o ON o.id = p.order_id
WHERE o.created_at >= '2026-09-01'
GROUP BY p.payment_method, o.status
ORDER BY p.payment_method, o.status;

-- 2) EXPLAIN: plan + ESTIMATES only. The query is NOT executed.
EXPLAIN
SELECT p.payment_method, o.status, count(*) AS payments, sum(p.amount) AS amount
FROM payments p
JOIN orders o ON o.id = p.order_id
WHERE o.created_at >= '2026-09-01'
GROUP BY p.payment_method, o.status
ORDER BY p.payment_method, o.status;

-- 3) EXPLAIN ANALYZE: EXECUTES the query, adds actual time / rows / loops.
EXPLAIN ANALYZE
SELECT p.payment_method, o.status, count(*) AS payments, sum(p.amount) AS amount
FROM payments p
JOIN orders o ON o.id = p.order_id
WHERE o.created_at >= '2026-09-01'
GROUP BY p.payment_method, o.status
ORDER BY p.payment_method, o.status;

-- 4) Full detail: buffers (I/O), output columns, non-default settings.
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS)
SELECT p.payment_method, o.status, count(*) AS payments, sum(p.amount) AS amount
FROM payments p
JOIN orders o ON o.id = p.order_id
WHERE o.created_at >= '2026-09-01'
GROUP BY p.payment_method, o.status
ORDER BY p.payment_method, o.status;

RESET enable_hashjoin;

-- Observe:
--   * Merge Join or Nested Loop - compare Buffers and time with the hash join

-- Undo only this strategy:
-- RESET enable_hashjoin;

-- Next: run 05_reset.sql, compare with 01_before.sql, then 05_reset.sql.
