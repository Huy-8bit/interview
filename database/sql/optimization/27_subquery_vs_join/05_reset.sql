-- =============================================================================
-- Lab 27 · Subquery vs JOIN: what the planner rewrites for you — RESET
-- Return the database to the exact state it had before this lab.
-- Safe to run any number of times (everything is IF EXISTS / idempotent).
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

-- Reset Strategy A: Q1 as JOIN + DISTINCT (the 'manual' rewrite)
-- (nothing to undo: query rewrite only)

-- Reset Strategy B: Q2: one grouped LEFT JOIN instead of two correlated subqueries
-- (nothing to undo: query rewrite only)

-- Session settings possibly changed by this lab
RESET ALL;

-- Verify: the objects created by this lab are gone
SELECT 'lab 27 creates no objects' AS note;

-- Full check of the whole database (expect a single row: BASELINE OK):
--   sql/optimization/00_environment/09_verify_baseline.sql
