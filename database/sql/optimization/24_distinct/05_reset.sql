-- =============================================================================
-- Lab 24 · DISTINCT: full scan vs emulated skip scan, count(DISTINCT) — RESET
-- Return the database to the exact state it had before this lab.
-- Safe to run any number of times (everything is IF EXISTS / idempotent).
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

-- Reset Strategy A: Rewrite Q1 as a recursive 'skip scan' (loose index scan emulation)
-- (nothing to undo: query rewrite only)

-- Reset Strategy B: Rewrite Q2: count(*) over SELECT DISTINCT
-- (nothing to undo: query rewrite only)

-- Session settings possibly changed by this lab
RESET ALL;

-- Verify: the objects created by this lab are gone
SELECT 'lab 24 creates no objects' AS note;

-- Full check of the whole database (expect a single row: BASELINE OK):
--   sql/optimization/00_environment/09_verify_baseline.sql
