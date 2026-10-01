-- =============================================================================
-- Lab 06 · Column order in a composite index: equality vs range — COMPARE
-- Before / after worksheet. Fill in YOUR numbers: timings depend on the machine,
-- the cache state and the dataset profile, so none are hard-coded here.
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

/*
BEFORE
------
  Q1 plan / Buffers / time:            Record your result here: 
  Q2 plan / Buffers / time:            Record your result here: 
  Q3 plan / Buffers / time:            Record your result here: 
  Index size:                          Record your result here: 

AFTER (Strategy A)
------------------
  Q1 plan / Buffers / time:            Record your result here: 
  Q2 plan / Buffers / time:            Record your result here: 
  Q3 plan / Buffers / time:            Record your result here: 
  Index size:                          Record your result here: 

AFTER (Strategy B)
------------------
  Q1 plan / Buffers / time:            Record your result here: 
  Q2 plan / Buffers / time:            Record your result here: 
  Q3 plan / Buffers / time:            Record your result here: 
  Index size:                          Record your result here: 

How to read the difference:
  Rule of thumb for a B-tree (a, b):
    a = ? AND b = ?          seek on (a, b)                              best
    a = ? AND b > ?          seek on a, range on b: contiguous slice     good
    a > ? AND b = ?          range on a, b only CHECKED on every entry   weaker
    b = ?   (no a)           cannot seek (PostgreSQL 16 has no skip scan) full index scan at best
  => equality columns first, then the range / ORDER BY column.

Where the numbers come from:
  Execution Time / Planning Time   last lines of EXPLAIN ANALYZE
  Buffers: shared hit=.. read=..    EXPLAIN (ANALYZE, BUFFERS), top node = whole query
  Rows Removed by Filter            the scan node that has the Filter: line
  Run each EXPLAIN ANALYZE 5-10 times and keep the median: the first run often reads
  pages into the cache (read=...), later runs find them there (hit=...).
*/

-- Measurements that do not depend on timing:
SELECT indexname, pg_size_pretty(pg_relation_size(format('%I', indexname)::regclass)) AS size
FROM pg_indexes WHERE tablename = 'reviews' ORDER BY 1;

