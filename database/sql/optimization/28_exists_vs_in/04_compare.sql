-- =============================================================================
-- Lab 28 · EXISTS vs IN, NOT EXISTS vs NOT IN (and the NULL trap) — COMPARE
-- Before / after worksheet. Fill in YOUR numbers: timings depend on the machine,
-- the cache state and the dataset profile, so none are hard-coded here.
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

/*
BEFORE
------
  IN plan / time:                      Record your result here: 
  EXISTS plan / time:                  Record your result here: 
  NOT EXISTS plan / time:              Record your result here: 
  NOT IN plan (EXPLAIN only):          Record your result here: 

AFTER (Strategy A)
------------------
  IN plan / time:                      Record your result here: 
  EXISTS plan / time:                  Record your result here: 
  NOT EXISTS plan / time:              Record your result here: 
  NOT IN plan (EXPLAIN only):          Record your result here: 

Where the numbers come from:
  Execution Time / Planning Time   last lines of EXPLAIN ANALYZE
  Buffers: shared hit=.. read=..    EXPLAIN (ANALYZE, BUFFERS), top node = whole query
  Rows Removed by Filter            the scan node that has the Filter: line
  Run each EXPLAIN ANALYZE 5-10 times and keep the median: the first run often reads
  pages into the cache (read=...), later runs find them there (hit=...).
*/

SELECT 'fill in the worksheet above' AS todo;
