-- =============================================================================
-- Lab 15 · Indexes are not free: INSERT / UPDATE / DELETE cost and WAL — AFTER
-- Same query again, with the optimization applied (02_optimize.sql or 02b/02c...).
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Q1. INSERT 200,000 rows
-- -----------------------------------------------------------------------------

-- DML: EXPLAIN ANALYZE really EXECUTES the statement -> always inside a transaction
-- that is rolled back, so the lab data never changes.
BEGIN;

EXPLAIN
INSERT INTO lab_write
SELECT * FROM orders WHERE id > 500000 AND id <= 700000;

EXPLAIN (ANALYZE, BUFFERS, WAL, VERBOSE)
INSERT INTO lab_write
SELECT * FROM orders WHERE id > 500000 AND id <= 700000;

ROLLBACK;

-- Observe:
--   * WAL: records=... fpi=... bytes=...  (top node): redo volume, also shipped to the replica
--   * Buffers: shared dirtied / written
--   * Execution Time

-- -----------------------------------------------------------------------------
-- Q2. UPDATE an indexed column (status) on 100,000 rows
-- -----------------------------------------------------------------------------

-- DML: EXPLAIN ANALYZE really EXECUTES the statement -> always inside a transaction
-- that is rolled back, so the lab data never changes.
BEGIN;

EXPLAIN
UPDATE lab_write SET status = 'CANCELLED'
WHERE id <= 100000;

EXPLAIN (ANALYZE, BUFFERS, WAL, VERBOSE)
UPDATE lab_write SET status = 'CANCELLED'
WHERE id <= 100000;

ROLLBACK;

-- Observe:
--   * With an index on status the UPDATE can never be HOT (heap-only tuple):
--   * every index gets a new entry for the new row version

-- -----------------------------------------------------------------------------
-- Q3. DELETE 50,000 rows
-- -----------------------------------------------------------------------------

-- DML: EXPLAIN ANALYZE really EXECUTES the statement -> always inside a transaction
-- that is rolled back, so the lab data never changes.
BEGIN;

EXPLAIN
DELETE FROM lab_write
WHERE id <= 50000;

EXPLAIN (ANALYZE, BUFFERS, WAL, VERBOSE)
DELETE FROM lab_write
WHERE id <= 50000;

ROLLBACK;

-- Observe:
--   * DELETE only marks heap tuples (xmax); index entries are cleaned later by VACUUM

-- Record the numbers in 04_compare.sql, then run 05_reset.sql.
