-- =============================================================================
-- Lab 16 · Nested Loop: small outer side + indexed inner lookups — RESET
-- Return the database to the exact state it had before this lab.
-- Safe to run any number of times (everything is IF EXISTS / idempotent).
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

-- Reset Strategy A: (experiment) SET enable_nestloop = off: what would the alternative cost?
RESET enable_nestloop;

-- Reset Strategy B: (experiment) Grow the outer side: when does the planner leave the Nested Loop?
-- (nothing to undo: no DDL, no settings)

-- Session settings possibly changed by this lab
RESET ALL;

-- Verify: the objects created by this lab are gone
SELECT 'lab 16 creates no objects' AS note;

-- Full check of the whole database (expect a single row: BASELINE OK):
--   sql/optimization/00_environment/09_verify_baseline.sql
