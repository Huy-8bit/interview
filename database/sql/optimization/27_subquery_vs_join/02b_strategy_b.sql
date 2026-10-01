-- =============================================================================
-- Lab 27 · Subquery vs JOIN: what the planner rewrites for you — OPTIMIZE · Strategy B
-- Strategy B: Q2: one grouped LEFT JOIN instead of two correlated subqueries
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

-- Start from the baseline: run 05_reset.sql first if another strategy is still applied.

-- What / why:
-- Compute count and max for all the users of the range in one pass over their
-- orders (GROUP BY user_id), then LEFT JOIN it (LEFT keeps users without orders,
-- like the scalar subqueries that return 0 / NULL). 03_after.sql runs it.

-- Undo only this strategy:
-- -- (nothing to undo: query rewrite only)

-- Next: run 03_after.sql, compare with 01_before.sql, then 05_reset.sql.
