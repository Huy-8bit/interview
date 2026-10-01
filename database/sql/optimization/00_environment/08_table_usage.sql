-- =============================================================================
-- 00_environment / 08 · Table access patterns
-- =============================================================================

SELECT relname          AS table_name,
       seq_scan,                         -- full table scans started
       seq_tup_read,                     -- rows read by those scans
       idx_scan,                         -- index scans on this table (all its indexes)
       idx_tup_fetch,                    -- rows fetched through indexes
       round(seq_tup_read::numeric / nullif(seq_scan, 0)) AS avg_rows_per_seq_scan,
       n_live_tup, n_dead_tup,
       round(100.0 * n_dead_tup / nullif(n_live_tup + n_dead_tup, 0), 1) AS dead_pct,
       n_tup_ins, n_tup_upd, n_tup_hot_upd, n_tup_del,
       last_autovacuum, last_autoanalyze
FROM pg_stat_user_tables
ORDER BY seq_tup_read DESC;

-- Heap I/O
SELECT relname, heap_blks_hit, heap_blks_read, idx_blks_hit, idx_blks_read,
       round(100.0 * heap_blks_hit / nullif(heap_blks_hit + heap_blks_read, 0), 1) AS heap_hit_pct
FROM pg_statio_user_tables
ORDER BY heap_blks_read DESC;
