-- =============================================================================
-- Lab 40 · Partition pruning: scan only the relevant partitions — RESET
-- Return the database to the exact state it had before this lab.
-- Safe to run any number of times (everything is IF EXISTS / idempotent).
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

-- Reset Strategy A: Range partitioning by month
DROP TABLE IF EXISTS lab_orders_part;   -- drops all its partitions

DROP TABLE IF EXISTS lab_orders_part;
DROP TABLE IF EXISTS lab_orders_flat;

-- Session settings possibly changed by this lab
RESET ALL;

-- Verify: the objects created by this lab are gone
SELECT count(*) AS lab_partition_tables_left FROM pg_class WHERE relname LIKE 'lab\_orders\_%';   -- 0

-- Full check of the whole database (expect a single row: BASELINE OK):
--   sql/optimization/00_environment/09_verify_baseline.sql
