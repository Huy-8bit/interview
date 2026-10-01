-- =============================================================================
-- 00_environment / 07 · Index usage and I/O
-- Counters accumulate since the last stats reset. To measure one experiment:
--   SELECT pg_stat_reset();   (resets this database's counters; harmless in the lab)
-- =============================================================================

-- How often each index is used, and how many entries it returns
SELECT relname        AS table_name,
       indexrelname   AS index_name,
       idx_scan,                 -- number of index scans started
       idx_tup_read,             -- index entries returned by scans
       idx_tup_fetch,            -- live heap rows fetched by simple index scans
       last_idx_scan,            -- PG16+
       pg_size_pretty(pg_relation_size(indexrelid)) AS size
FROM pg_stat_user_indexes
ORDER BY idx_scan DESC, pg_relation_size(indexrelid) DESC;

-- Buffer I/O per index: hit = found in shared_buffers, read = had to be read in (OS cache or disk)
SELECT relname AS table_name, indexrelname AS index_name,
       idx_blks_hit, idx_blks_read,
       round(100.0 * idx_blks_hit / nullif(idx_blks_hit + idx_blks_read, 0), 1) AS hit_pct
FROM pg_statio_user_indexes
ORDER BY idx_blks_read DESC;

-- Definitions
SELECT tablename, indexname, indexdef FROM pg_indexes WHERE schemaname = 'public' ORDER BY tablename, indexname;

-- Never used, not backing a constraint (candidates to drop - after checking replicas too!)
SELECT s.relname, s.indexrelname, pg_size_pretty(pg_relation_size(s.indexrelid)) AS size
FROM pg_stat_user_indexes s
WHERE s.idx_scan = 0
  AND NOT EXISTS (SELECT 1 FROM pg_constraint c WHERE c.conindid = s.indexrelid)
ORDER BY pg_relation_size(s.indexrelid) DESC;
