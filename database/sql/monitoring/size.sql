-- =============================================================================
-- Database / table / index sizes, row estimates, index usage, bloat
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Databases
-- -----------------------------------------------------------------------------
SELECT datname, pg_size_pretty(pg_database_size(datname)) AS size
FROM pg_database
ORDER BY pg_database_size(datname) DESC;

-- -----------------------------------------------------------------------------
-- Tables: heap vs indexes vs TOAST, and estimated rows
--   pg_relation_size(t)       = main heap fork only
--   pg_table_size(t)          = heap + TOAST + FSM + VM
--   pg_indexes_size(t)        = all indexes of t
--   pg_total_relation_size(t) = pg_table_size + pg_indexes_size
--   reltuples                 = planner's row estimate (updated by VACUUM/ANALYZE) - free, no count(*)
-- -----------------------------------------------------------------------------
SELECT c.relname                                              AS table_name,
       c.reltuples::bigint                                    AS estimated_rows,
       s.n_live_tup                                           AS live_tuples,
       s.n_dead_tup                                           AS dead_tuples,
       c.relpages                                             AS pages_8kb,
       pg_size_pretty(pg_relation_size(c.oid))                AS heap,
       pg_size_pretty(pg_table_size(c.oid) - pg_relation_size(c.oid)) AS toast_fsm_vm,
       pg_size_pretty(pg_indexes_size(c.oid))                 AS indexes,
       pg_size_pretty(pg_total_relation_size(c.oid))          AS total,
       round(100.0 * pg_indexes_size(c.oid) / nullif(pg_total_relation_size(c.oid), 0), 1) AS index_pct
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
LEFT JOIN pg_stat_user_tables s ON s.relid = c.oid
WHERE c.relkind = 'r' AND n.nspname = 'public'
ORDER BY pg_total_relation_size(c.oid) DESC;

-- Exact count vs estimate (count(*) must read the whole table or an index!)
SELECT (SELECT count(*) FROM orders)                                  AS exact,
       (SELECT reltuples::bigint FROM pg_class WHERE oid = 'orders'::regclass) AS estimate;

-- -----------------------------------------------------------------------------
-- Indexes: size, how often used, definition
-- -----------------------------------------------------------------------------
SELECT s.relname                                       AS table_name,
       s.indexrelname                                  AS index_name,
       pg_size_pretty(pg_relation_size(s.indexrelid))  AS index_size,
       s.idx_scan                                      AS scans,
       s.idx_tup_read, s.idx_tup_fetch,
       i.indisunique                                   AS is_unique,
       pg_get_indexdef(s.indexrelid)                   AS definition
FROM pg_stat_user_indexes s
JOIN pg_index i ON i.indexrelid = s.indexrelid
ORDER BY pg_relation_size(s.indexrelid) DESC;

-- Unused indexes (idx_scan = 0) that are not backing a constraint
SELECT s.relname AS table_name, s.indexrelname AS index_name,
       pg_size_pretty(pg_relation_size(s.indexrelid)) AS size
FROM pg_stat_user_indexes s
JOIN pg_index i ON i.indexrelid = s.indexrelid
WHERE s.idx_scan = 0
  AND NOT i.indisunique
  AND NOT EXISTS (SELECT 1 FROM pg_constraint c WHERE c.conindid = s.indexrelid)
ORDER BY pg_relation_size(s.indexrelid) DESC;

-- Sequential vs index scans per table (lots of seq_tup_read on a big table = missing index?)
SELECT relname, seq_scan, seq_tup_read, idx_scan,
       CASE WHEN seq_scan > 0 THEN seq_tup_read / seq_scan END AS avg_rows_per_seq_scan
FROM pg_stat_user_tables
ORDER BY seq_tup_read DESC;

-- -----------------------------------------------------------------------------
-- Cache hit ratio (shared_buffers). ~99% on a warm OLTP system.
-- -----------------------------------------------------------------------------
SELECT relname,
       heap_blks_read, heap_blks_hit,
       round(100.0 * heap_blks_hit / nullif(heap_blks_hit + heap_blks_read, 0), 2) AS heap_hit_pct,
       round(100.0 * idx_blks_hit  / nullif(idx_blks_hit + idx_blks_read, 0), 2)   AS idx_hit_pct
FROM pg_statio_user_tables
ORDER BY heap_blks_read + heap_blks_hit DESC;

-- -----------------------------------------------------------------------------
-- Exact bloat of one table (reads the whole table - pgstattuple extension)
-- -----------------------------------------------------------------------------
SELECT * FROM pgstattuple('orders');
SELECT * FROM pgstatindex('idx_orders_created_at');

-- Autovacuum / analyze history
SELECT relname, n_live_tup, n_dead_tup, n_mod_since_analyze,
       last_vacuum, last_autovacuum, last_analyze, last_autoanalyze, vacuum_count, autovacuum_count
FROM pg_stat_user_tables
ORDER BY n_dead_tup DESC;
