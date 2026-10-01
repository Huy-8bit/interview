-- =============================================================================
-- Lab 37 · Table bloat: VACUUM FULL vs CLUSTER — COMPARE
-- Before / after worksheet. Fill in YOUR numbers: timings depend on the machine,
-- the cache state and the dataset profile, so none are hard-coded here.
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

/*
BEFORE
------
  Table size / free_pct:               Record your result here: 
  Q1 Buffers / time:                   Record your result here: 
  Q2 Heap Blocks / time:               Record your result here: 
  correlation of user_id:              Record your result here: 

AFTER (Strategy A)
------------------
  Table size / free_pct:               Record your result here: 
  Q1 Buffers / time:                   Record your result here: 
  Q2 Heap Blocks / time:               Record your result here: 
  correlation of user_id:              Record your result here: 

AFTER (Strategy B)
------------------
  Table size / free_pct:               Record your result here: 
  Q1 Buffers / time:                   Record your result here: 
  Q2 Heap Blocks / time:               Record your result here: 
  correlation of user_id:              Record your result here: 

Where the numbers come from:
  Execution Time / Planning Time   last lines of EXPLAIN ANALYZE
  Buffers: shared hit=.. read=..    EXPLAIN (ANALYZE, BUFFERS), top node = whole query
  Rows Removed by Filter            the scan node that has the Filter: line
  Run each EXPLAIN ANALYZE 5-10 times and keep the median: the first run often reads
  pages into the cache (read=...), later runs find them there (hit=...).
*/

-- Measurements that do not depend on timing:
SELECT tuple_count, round(free_percent::numeric, 1) AS free_pct, pg_size_pretty(table_len) AS table_size
FROM pgstattuple('lab_bloat');

