-- =============================================================================
-- Lab 11 · Implicit casts that disable an index — OPTIMIZE · Strategy A
-- Strategy A: Fix the types in the query (cast the VALUE, never the column)
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

-- What / why:
-- PostgreSQL resolves 'col = value' by choosing an operator for the two types;
-- when they differ it converts one side - sometimes the column. A cast on the
-- column hides it from the index. Pass parameters in the column's own type.
-- 03_after.sql runs the corrected queries. No DDL.

-- Undo only this strategy:
-- -- (nothing to undo: query rewrite only)

-- Next: run 03_after.sql, compare with 01_before.sql, then 05_reset.sql.
