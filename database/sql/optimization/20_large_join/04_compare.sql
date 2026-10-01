-- =============================================================================
-- Lab 20 · Large join: a 5-table revenue report — COMPARE
-- Before / after worksheet. Fill in YOUR numbers: timings depend on the machine,
-- the cache state and the dataset profile, so none are hard-coded here.
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

/*
BEFORE
------
  Plan shape (join types, Memoize?):   Record your result here: 
  Rows into the products join:         Record your result here: 
  Buffers:                             Record your result here: 
  Execution Time:                      Record your result here: 

AFTER (Strategy A)
------------------
  Plan shape (join types, Memoize?):   Record your result here: 
  Rows into the products join:         Record your result here: 
  Buffers:                             Record your result here: 
  Execution Time:                      Record your result here: 

AFTER (Strategy B)
------------------
  Plan shape (join types, Memoize?):   Record your result here: 
  Rows into the products join:         Record your result here: 
  Buffers:                             Record your result here: 
  Execution Time:                      Record your result here: 

AFTER (Strategy C)
------------------
  Plan shape (join types, Memoize?):   Record your result here: 
  Rows into the products join:         Record your result here: 
  Buffers:                             Record your result here: 
  Execution Time:                      Record your result here: 

Where the numbers come from:
  Execution Time / Planning Time   last lines of EXPLAIN ANALYZE
  Buffers: shared hit=.. read=..    EXPLAIN (ANALYZE, BUFFERS), top node = whole query
  Rows Removed by Filter            the scan node that has the Filter: line
  Run each EXPLAIN ANALYZE 5-10 times and keep the median: the first run often reads
  pages into the cache (read=...), later runs find them there (hit=...).
*/

-- Measurements that do not depend on timing:
SELECT indexname, pg_size_pretty(pg_relation_size(format('%I', indexname)::regclass)) AS size
FROM pg_indexes WHERE tablename = 'products' ORDER BY 1;

