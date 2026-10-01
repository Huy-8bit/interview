-- =============================================================================
-- Lab 39 · Buffer cache: shared hit vs read, cold vs warm, working set — COMPARE
-- Before / after worksheet. Fill in YOUR numbers: timings depend on the machine,
-- the cache state and the dataset profile, so none are hard-coded here.
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

/*
BEFORE
------
  1st run: Buffers hit / read, time:   Record your result here: 
  2nd run: Buffers hit / read, time:   Record your result here: 
  After strategy A: Buffers / time:    Record your result here: 
  pg_buffercache: buffers of orders / of the index: Record your result here: 

AFTER (Strategy A)
------------------
  1st run: Buffers hit / read, time:   Record your result here: 
  2nd run: Buffers hit / read, time:   Record your result here: 
  After strategy A: Buffers / time:    Record your result here: 
  pg_buffercache: buffers of orders / of the index: Record your result here: 

How to read the difference:
  shared hit  = the page was already in PostgreSQL's shared_buffers
  shared read = PostgreSQL had to ask the OS for it: the OS may serve it from its own
                page cache (fast, no disk I/O) or from disk (slow). EXPLAIN cannot tell
                which - track_io_timing (on in this lab) shows the time spent in reads.
  Benchmark rule: run 5-10 times, compare medians, and compare BUFFERS, not only time.

Where the numbers come from:
  Execution Time / Planning Time   last lines of EXPLAIN ANALYZE
  Buffers: shared hit=.. read=..    EXPLAIN (ANALYZE, BUFFERS), top node = whole query
  Rows Removed by Filter            the scan node that has the Filter: line
  Run each EXPLAIN ANALYZE 5-10 times and keep the median: the first run often reads
  pages into the cache (read=...), later runs find them there (hit=...).
*/

-- Measurements that do not depend on timing:
-- Which relations occupy shared_buffers right now (pg_buffercache, 8 KB per buffer)
SELECT c.relname, count(*) AS buffers, pg_size_pretty(count(*) * 8192) AS cached,
       round(100.0 * count(*) / (SELECT setting::int FROM pg_settings WHERE name = 'shared_buffers'), 1) AS pct_of_shared_buffers
FROM pg_buffercache b
JOIN pg_class c ON b.relfilenode = pg_relation_filenode(c.oid)
               AND b.reldatabase = (SELECT oid FROM pg_database WHERE datname = current_database())
GROUP BY c.relname
ORDER BY buffers DESC
LIMIT 10;

