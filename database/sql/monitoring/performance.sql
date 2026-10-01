-- =============================================================================
-- Query performance: pg_stat_statements, WAL volume, checkpoints, settings
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Top queries by total execution time (normalised: literals replaced by $1, $2)
-- -----------------------------------------------------------------------------
SELECT queryid,
       calls,
       round(total_exec_time::numeric, 1)              AS total_ms,
       round(mean_exec_time::numeric, 2)               AS mean_ms,
       round(stddev_exec_time::numeric, 2)             AS stddev_ms,
       rows,
       shared_blks_hit, shared_blks_read,               -- read = had to come from disk / OS cache
       round(100.0 * shared_blks_hit / nullif(shared_blks_hit + shared_blks_read, 0), 1) AS hit_pct,
       temp_blks_written,                               -- > 0 : sorts/hashes spilled to disk (work_mem)
       pg_size_pretty(wal_bytes)                        AS wal,
       left(query, 150)                                 AS query
FROM pg_stat_statements
WHERE dbid = (SELECT oid FROM pg_database WHERE datname = current_database())
ORDER BY total_exec_time DESC
LIMIT 20;

-- Slowest on average (at least 5 calls)
SELECT calls, round(mean_exec_time::numeric, 2) AS mean_ms, rows / nullif(calls, 0) AS rows_per_call,
       left(query, 150) AS query
FROM pg_stat_statements
WHERE calls >= 5
ORDER BY mean_exec_time DESC
LIMIT 20;

-- Reset the statistics before an experiment
-- SELECT pg_stat_statements_reset();

-- -----------------------------------------------------------------------------
-- WAL generation (how much redo your workload produces)
-- -----------------------------------------------------------------------------
SELECT wal_records, wal_fpi,                       -- fpi = full-page images (first change after a checkpoint)
       pg_size_pretty(wal_bytes) AS wal_bytes,
       wal_buffers_full,                          -- > 0 : wal_buffers too small for the write burst
       wal_write, wal_sync, stats_reset
FROM pg_stat_wal;

-- Measure the WAL produced by one statement:
--   SELECT pg_current_wal_lsn();                      -- note it, e.g. 0/7A000000
--   UPDATE products SET price = price WHERE id <= 1000;
--   SELECT pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), '0/7A000000'));

-- -----------------------------------------------------------------------------
-- Checkpoints & background writer
-- -----------------------------------------------------------------------------
SELECT checkpoints_timed,                          -- triggered by checkpoint_timeout (good)
       checkpoints_req,                            -- triggered by max_wal_size (bulk load, or too small)
       round((checkpoint_write_time / 1000)::numeric, 1) AS write_s,
       round((checkpoint_sync_time / 1000)::numeric, 1)  AS sync_s,
       buffers_checkpoint, buffers_clean, buffers_backend, stats_reset
FROM pg_stat_bgwriter;

-- -----------------------------------------------------------------------------
-- Temporary files (work_mem too small for a sort / hash)
-- -----------------------------------------------------------------------------
SELECT datname, temp_files, pg_size_pretty(temp_bytes) AS temp_bytes
FROM pg_stat_database
WHERE datname = current_database();

-- -----------------------------------------------------------------------------
-- Non-default settings of this server
-- -----------------------------------------------------------------------------
SELECT name, setting, unit, source, short_desc
FROM pg_settings
WHERE source NOT IN ('default', 'override')
ORDER BY name;

-- -----------------------------------------------------------------------------
-- What is in shared_buffers right now (pg_buffercache)
-- -----------------------------------------------------------------------------
SELECT c.relname,
       count(*)                                          AS buffers,
       pg_size_pretty(count(*) * 8192)                   AS cached,
       round(100.0 * count(*) / (SELECT setting::int FROM pg_settings WHERE name = 'shared_buffers'), 1)
                                                         AS pct_of_shared_buffers,
       count(*) FILTER (WHERE b.isdirty)                 AS dirty
FROM pg_buffercache b
JOIN pg_class c ON b.relfilenode = pg_relation_filenode(c.oid)
WHERE b.reldatabase = (SELECT oid FROM pg_database WHERE datname = current_database())
GROUP BY c.relname
ORDER BY buffers DESC
LIMIT 15;
