-- =============================================================================
-- Lab 02 · Selectivity: the same index, different plans — COMPARE
-- Before / after worksheet. Fill in YOUR numbers: timings depend on the machine,
-- the cache state and the dataset profile, so none are hard-coded here.
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

/*
BEFORE
------
  Plan for SUCCEEDED:                  Record your result here: 
  Plan for PENDING:                    Record your result here: 
  Plan for REFUNDED:                   Record your result here: 
  Estimated rows (each query):         Record your result here: 
  Actual rows (each query):            Record your result here: 
  Buffers (each query):                Record your result here: 
  Execution Time (each query):         Record your result here: 
  Index size:                          Record your result here: 

AFTER (Strategy A)
------------------
  Plan for SUCCEEDED:                  Record your result here: 
  Plan for PENDING:                    Record your result here: 
  Plan for REFUNDED:                   Record your result here: 
  Estimated rows (each query):         Record your result here: 
  Actual rows (each query):            Record your result here: 
  Buffers (each query):                Record your result here: 
  Execution Time (each query):         Record your result here: 
  Index size:                          Record your result here: 

AFTER (Strategy B)
------------------
  Plan for SUCCEEDED:                  Record your result here: 
  Plan for PENDING:                    Record your result here: 
  Plan for REFUNDED:                   Record your result here: 
  Estimated rows (each query):         Record your result here: 
  Actual rows (each query):            Record your result here: 
  Buffers (each query):                Record your result here: 
  Execution Time (each query):         Record your result here: 
  Index size:                          Record your result here: 

How to read the difference:
  Selectivity = fraction of rows that match. The cost model compares
    Seq Scan     ~ seq_page_cost * all pages + cpu_tuple_cost * all rows
    Index/Bitmap ~ index pages + random_page_cost * matching heap pages + cpu costs
  The cheaper estimate wins. Low selectivity (few rows) -> index; high -> Seq Scan.

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

