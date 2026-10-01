-- =============================================================================
-- 00_environment / 02 · Table sizes: heap vs indexes vs TOAST, row estimates
-- Index-related labs change these numbers: compare before / after optimization.
-- =============================================================================

SELECT c.relname                                              AS table_name,
       to_char(c.reltuples, 'FM999,999,999')                  AS est_rows,     -- from the last ANALYZE/VACUUM
       c.relpages                                             AS heap_pages,   -- 8 KB pages
       pg_size_pretty(pg_relation_size(c.oid))                AS heap,
       pg_size_pretty(pg_indexes_size(c.oid))                 AS indexes,
       pg_size_pretty(pg_total_relation_size(c.oid)
                      - pg_relation_size(c.oid)
                      - pg_indexes_size(c.oid))               AS toast_and_maps,
       pg_size_pretty(pg_total_relation_size(c.oid))          AS total,
       round(100.0 * pg_indexes_size(c.oid) / nullif(pg_total_relation_size(c.oid), 0), 1) AS index_pct
FROM pg_class c
WHERE c.relnamespace = 'public'::regnamespace
  AND c.relkind IN ('r', 'p', 'm')
ORDER BY pg_total_relation_size(c.oid) DESC;

-- Size of one table / index (use this pattern in every index lab):
--   SELECT pg_size_pretty(pg_relation_size('orders'));            -- heap only
--   SELECT pg_size_pretty(pg_indexes_size('orders'));             -- all indexes of the table
--   SELECT pg_size_pretty(pg_total_relation_size('orders'));      -- heap + indexes + TOAST
--   SELECT pg_size_pretty(pg_relation_size('idx_orders_user_id')); -- one index
