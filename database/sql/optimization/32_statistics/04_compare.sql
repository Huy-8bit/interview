-- =============================================================================
-- Lab 32 · Planner statistics: n_distinct, MCV, histogram, correlation — COMPARE
-- Before / after worksheet. Fill in YOUR numbers: timings depend on the machine,
-- the cache state and the dataset profile, so none are hard-coded here.
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

/*
BEFORE
------
  Q1 estimated vs actual groups:       Record your result here: 
  Q2 estimated vs actual rows:         Record your result here: 
  Q3 estimated vs actual rows:         Record your result here: 
  pg_stats.n_distinct for user_id:     Record your result here: 

AFTER (Strategy A)
------------------
  Q1 estimated vs actual groups:       Record your result here: 
  Q2 estimated vs actual rows:         Record your result here: 
  Q3 estimated vs actual rows:         Record your result here: 
  pg_stats.n_distinct for user_id:     Record your result here: 

AFTER (Strategy B)
------------------
  Q1 estimated vs actual groups:       Record your result here: 
  Q2 estimated vs actual rows:         Record your result here: 
  Q3 estimated vs actual rows:         Record your result here: 
  pg_stats.n_distinct for user_id:     Record your result here: 

Where the numbers come from:
  Execution Time / Planning Time   last lines of EXPLAIN ANALYZE
  Buffers: shared hit=.. read=..    EXPLAIN (ANALYZE, BUFFERS), top node = whole query
  Rows Removed by Filter            the scan node that has the Filter: line
  Run each EXPLAIN ANALYZE 5-10 times and keep the median: the first run often reads
  pages into the cache (read=...), later runs find them there (hit=...).
*/

-- Measurements that do not depend on timing:
SELECT attname, null_frac, n_distinct, array_length(most_common_vals::text::text[], 1) AS n_mcv,
       array_length(histogram_bounds::text::text[], 1) AS n_histogram_bounds, round(correlation::numeric, 3) AS correlation
FROM pg_stats WHERE tablename = 'orders' AND attname IN ('user_id', 'status', 'total_amount', 'created_at')
ORDER BY attname;

