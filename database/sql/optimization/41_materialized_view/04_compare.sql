-- =============================================================================
-- Lab 41 · Materialized view: precompute an expensive aggregate — COMPARE
-- Before / after worksheet. Fill in YOUR numbers: timings depend on the machine,
-- the cache state and the dataset profile, so none are hard-coded here.
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

/*
BEFORE
------
  Live query: Buffers / time:          Record your result here: 
  MV query: Buffers / time:            Record your result here: 
  REFRESH time (\timing in psql):      Record your result here: 
  MV size:                             Record your result here: 

AFTER (Strategy A)
------------------
  Live query: Buffers / time:          Record your result here: 
  MV query: Buffers / time:            Record your result here: 
  REFRESH time (\timing in psql):      Record your result here: 
  MV size:                             Record your result here: 

How to read the difference:
  Freshness vs speed: the MV is stale between refreshes. Typical pattern: REFRESH ...
  CONCURRENTLY from a scheduler (cron / pg_cron) every N minutes; for real-time numbers
  maintain a summary table with triggers or in the application instead.

Where the numbers come from:
  Execution Time / Planning Time   last lines of EXPLAIN ANALYZE
  Buffers: shared hit=.. read=..    EXPLAIN (ANALYZE, BUFFERS), top node = whole query
  Rows Removed by Filter            the scan node that has the Filter: line
  Run each EXPLAIN ANALYZE 5-10 times and keep the median: the first run often reads
  pages into the cache (read=...), later runs find them there (hit=...).
*/

SELECT 'fill in the worksheet above' AS todo;
