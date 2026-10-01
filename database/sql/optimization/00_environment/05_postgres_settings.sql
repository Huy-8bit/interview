-- =============================================================================
-- 00_environment / 05 · Settings that change plans
-- The labs only use SET (session scope) and always RESET afterwards.
-- =============================================================================

SELECT name, setting, unit, source, short_desc
FROM pg_settings
WHERE name IN (
  -- memory
  'shared_buffers', 'work_mem', 'hash_mem_multiplier', 'maintenance_work_mem', 'effective_cache_size',
  -- cost model
  'seq_page_cost', 'random_page_cost', 'cpu_tuple_cost', 'cpu_index_tuple_cost', 'cpu_operator_cost',
  'effective_io_concurrency', 'default_statistics_target',
  -- parallel query
  'max_parallel_workers_per_gather', 'max_parallel_workers', 'parallel_setup_cost', 'parallel_tuple_cost',
  'min_parallel_table_scan_size',
  -- plan types (all should be "on"; labs 16-18 switch some off temporarily)
  'enable_seqscan', 'enable_indexscan', 'enable_indexonlyscan', 'enable_bitmapscan',
  'enable_nestloop', 'enable_hashjoin', 'enable_mergejoin', 'enable_sort', 'enable_hashagg',
  'enable_incremental_sort', 'enable_memoize', 'enable_partition_pruning',
  'jit', 'track_io_timing')
ORDER BY name;

-- Anything changed in THIS session (should be empty after a lab's reset)
SELECT name, setting, reset_val
FROM pg_settings
WHERE source = 'session';
