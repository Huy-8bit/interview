-- =============================================================================
-- 00_environment / 03 · Every index: type, flags, definition, size, usage
-- =============================================================================

SELECT t.relname                                  AS table_name,
       i.relname                                  AS index_name,
       am.amname                                  AS type,          -- btree / gin / hash / brin ...
       ix.indisprimary                            AS is_pk,
       ix.indisunique                             AS is_unique,
       ix.indpred  IS NOT NULL                    AS is_partial,
       ix.indexprs IS NOT NULL                    AS is_expression,
       ix.indnatts - ix.indnkeyatts               AS include_cols,  -- > 0 = covering index (INCLUDE)
       ix.indisvalid                              AS is_valid,      -- false = failed CREATE INDEX CONCURRENTLY
       pg_size_pretty(pg_relation_size(i.oid))    AS size,
       s.idx_scan                                 AS scans_since_stats_reset,
       pg_get_indexdef(ix.indexrelid)             AS definition
FROM pg_index ix
JOIN pg_class i  ON i.oid = ix.indexrelid
JOIN pg_class t  ON t.oid = ix.indrelid
JOIN pg_am    am ON am.oid = i.relam
LEFT JOIN pg_stat_user_indexes s ON s.indexrelid = ix.indexrelid
WHERE t.relnamespace = 'public'::regnamespace
ORDER BY t.relname, i.relname;

-- Indexes created by the optimization labs (should be EMPTY when no lab is in progress)
SELECT indexname, tablename, pg_size_pretty(pg_relation_size(format('%I', indexname)::regclass)) AS size
FROM pg_indexes
WHERE schemaname = 'public' AND indexname LIKE 'ix\_lab%';
