-- =============================================================================
-- Lab 23 · GROUP BY: HashAggregate vs GroupAggregate — COMPARE
-- Before / after worksheet. Fill in YOUR numbers: timings depend on the machine,
-- the cache state and the dataset profile, so none are hard-coded here.
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

/*
BEFORE
------
  Q1 aggregate node:                   Record your result here: 
  Q2 aggregate node / Batches / Disk Usage: Record your result here: 
  Q2 time:                             Record your result here: 
  Index size:                          Record your result here: 

AFTER (Strategy A)
------------------
  Q1 aggregate node:                   Record your result here: 
  Q2 aggregate node / Batches / Disk Usage: Record your result here: 
  Q2 time:                             Record your result here: 
  Index size:                          Record your result here: 

AFTER (Strategy B)
------------------
  Q1 aggregate node:                   Record your result here: 
  Q2 aggregate node / Batches / Disk Usage: Record your result here: 
  Q2 time:                             Record your result here: 
  Index size:                          Record your result here: 

How to read the difference:
  HashAggregate: input in any order, memory ~ number of groups, spills to disk if too big.
  GroupAggregate: input must be sorted by the group key (Sort node or ordered index),
                  memory ~ one group, streams results (good with LIMIT).

Where the numbers come from:
  Execution Time / Planning Time   last lines of EXPLAIN ANALYZE
  Buffers: shared hit=.. read=..    EXPLAIN (ANALYZE, BUFFERS), top node = whole query
  Rows Removed by Filter            the scan node that has the Filter: line
  Run each EXPLAIN ANALYZE 5-10 times and keep the median: the first run often reads
  pages into the cache (read=...), later runs find them there (hit=...).
*/

-- Measurements that do not depend on timing:
SELECT indexname, pg_size_pretty(pg_relation_size(format('%I', indexname)::regclass)) AS size
FROM pg_indexes WHERE tablename = 'orders' ORDER BY 1;

