-- =============================================================================
-- 00_environment / 04 · Planner statistics (what the cost model "knows")
-- pg_stats is filled by ANALYZE (and autovacuum's auto-analyze).
-- =============================================================================

-- When were the tables last analyzed / vacuumed?
SELECT relname, n_live_tup, n_dead_tup, n_mod_since_analyze,
       last_analyze, last_autoanalyze, last_vacuum, last_autovacuum
FROM pg_stat_user_tables
ORDER BY relname;

-- Column statistics of the most-used columns
--   null_frac          fraction of NULLs
--   n_distinct         > 0: number of distinct values; < 0: -(distinct / rows), e.g. -1 = unique
--   most_common_vals / most_common_freqs   MCV list: values and their frequencies
--   histogram_bounds   equal-population buckets for the values NOT in the MCV list
--   correlation        physical order vs value order: 1 / -1 = sorted on disk, 0 = random
SELECT tablename, attname, null_frac, n_distinct,
       left(most_common_vals::text, 60)  AS most_common_vals,
       left(most_common_freqs::text, 60) AS most_common_freqs,
       left(histogram_bounds::text, 60)  AS histogram_bounds,
       round(correlation::numeric, 3)    AS correlation
FROM pg_stats
WHERE schemaname = 'public'
  AND (tablename, attname) IN (('orders', 'status'), ('orders', 'user_id'), ('orders', 'created_at'),
                               ('orders', 'total_amount'), ('users', 'phone'), ('users', 'status'),
                               ('products', 'category_id'), ('payments', 'status'),
                               ('addresses', 'country_code'), ('addresses', 'city'), ('reviews', 'rating'))
ORDER BY tablename, attname;

-- Per-column statistics target (-1 = default_statistics_target) - lab 32 changes one of them
SELECT attrelid::regclass AS table_name, attname, attstattarget
FROM pg_attribute
WHERE attrelid IN (SELECT oid FROM pg_class WHERE relnamespace = 'public'::regnamespace AND relkind = 'r')
  AND attnum > 0 AND NOT attisdropped AND attstattarget <> -1;

-- Extended statistics (CREATE STATISTICS) - labs 33 / 34 create and drop them
SELECT statistics_name, tablename, attnames, kinds FROM pg_stats_ext WHERE schemaname = 'public';
