-- =============================================================================
-- Lab 15 · Indexes are not free: INSERT / UPDATE / DELETE cost and WAL — BEFORE (baseline)
-- The query as it runs today, before any optimization.
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

-- Lab table with the shape of orders and 500,000 rows, only a primary key.
-- Re-created every time this file runs. The DML below runs in transactions that are
-- ROLLED BACK, so every run measures the same thing.
DROP TABLE IF EXISTS lab_write;
CREATE TABLE lab_write (LIKE orders INCLUDING DEFAULTS);
ALTER TABLE lab_write ADD PRIMARY KEY (id);
INSERT INTO lab_write SELECT * FROM orders WHERE id <= 500000;
VACUUM (ANALYZE) lab_write;
SELECT pg_size_pretty(pg_relation_size('lab_write')) AS heap, pg_size_pretty(pg_indexes_size('lab_write')) AS indexes;

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

-- Observe in every plan:
--   * Scan / join type of every node (Seq Scan, Index Scan, Bitmap Heap Scan, Hash Join ...)
--   * cost=startup..total  (planner units, NOT milliseconds)
--   * rows= estimated  vs  actual rows=  (x loops)  -> how wrong is the estimate?
--   * Rows Removed by Filter: rows read and thrown away
--   * Buffers: shared hit (already in shared_buffers) / read (fetched from OS cache or disk)
--   * Planning Time / Execution Time (run 5-10 times, keep the typical value)

-- Record the numbers in 04_compare.sql, then run 02_optimize.sql.
