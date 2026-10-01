-- =============================================================================
-- Lab 21 · ORDER BY ... LIMIT: top-N heapsort vs Index Scan Backward — COMPARE
-- Before / after worksheet. Fill in YOUR numbers: timings depend on the machine,
-- the cache state and the dataset profile, so none are hard-coded here.
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

/*
BEFORE
------
  Q1 plan (Sort? Index Scan Backward?): Record your result here: 
  Q1 Buffers / time:                   Record your result here: 
  Q2 plan / Rows Removed by Filter:    Record your result here: 
  Q2 Buffers / time:                   Record your result here: 
  Index size:                          Record your result here: 

AFTER (Strategy A)
------------------
  Q1 plan (Sort? Index Scan Backward?): Record your result here: 
  Q1 Buffers / time:                   Record your result here: 
  Q2 plan / Rows Removed by Filter:    Record your result here: 
  Q2 Buffers / time:                   Record your result here: 
  Index size:                          Record your result here: 

AFTER (Strategy B)
------------------
  Q1 plan (Sort? Index Scan Backward?): Record your result here: 
  Q1 Buffers / time:                   Record your result here: 
  Q2 plan / Rows Removed by Filter:    Record your result here: 
  Q2 Buffers / time:                   Record your result here: 
  Index size:                          Record your result here: 

Where the numbers come from:
  Execution Time / Planning Time   last lines of EXPLAIN ANALYZE
  Buffers: shared hit=.. read=..    EXPLAIN (ANALYZE, BUFFERS), top node = whole query
  Rows Removed by Filter            the scan node that has the Filter: line
  Run each EXPLAIN ANALYZE 5-10 times and keep the median: the first run often reads
  pages into the cache (read=...), later runs find them there (hit=...).
*/

-- Measurements that do not depend on timing:
SELECT indexname, pg_size_pretty(pg_relation_size(format('%I', indexname)::regclass)) AS size
FROM pg_indexes WHERE tablename = 'payments' ORDER BY 1;

