-- =============================================================================
-- Lab 31 · Query rewrites: count > 0, HAVING, UNION, SELECT * — OPTIMIZE · Strategy A
-- Strategy A: Rewrite each query (no DDL)
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

-- What / why:
-- Q1: EXISTS stops at the first matching row. Q2: put the filter in WHERE (the
-- planner already did it - writing it explicitly documents the intent).
-- Q3: UNION ALL when duplicates do not matter or cannot occur (no de-dup step).
-- Q4: select only the needed columns: narrower rows = smaller sorts and less I/O
-- to the client. 03_after.sql runs the rewritten versions.

-- Undo only this strategy:
-- -- (nothing to undo: query rewrite only)

-- Next: run 03_after.sql, compare with 01_before.sql, then 05_reset.sql.
