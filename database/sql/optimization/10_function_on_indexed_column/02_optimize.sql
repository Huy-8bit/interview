-- =============================================================================
-- Lab 10 · Function on an indexed column (sargable queries) — OPTIMIZE · Strategy A
-- Strategy A: Rewrite as a half-open range on the bare column (sargable)
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

-- What / why:
-- 'Sargable' = Search ARGument ABLE: the column stands alone on one side of
-- the operator, so the B-tree on created_at can seek directly to the range.
-- Half-open [start, end) avoids the 23:59:59.999 trap and works for any type.
-- 03_after.sql runs the rewritten queries. No DDL.

-- Undo only this strategy:
-- -- (nothing to undo: query rewrite only)

-- Next: run 03_after.sql, compare with 01_before.sql, then 05_reset.sql.
