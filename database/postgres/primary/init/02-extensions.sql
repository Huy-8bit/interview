-- -----------------------------------------------------------------------------
-- The `ecommerce` database itself is created by the official image from
-- POSTGRES_DB. This script prepares it: extensions + database-level defaults.
-- Runs connected to POSTGRES_DB.
-- -----------------------------------------------------------------------------

-- Query statistics: SELECT * FROM pg_stat_statements ORDER BY total_exec_time DESC;
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
-- Trigram similarity: fast ILIKE '%foo%' with a GIN/GiST index (index lab)
CREATE EXTENSION IF NOT EXISTS pg_trgm;
-- Look inside heap/index pages: tuple headers, xmin/xmax, line pointers (MVCC lab)
CREATE EXTENSION IF NOT EXISTS pageinspect;
-- Dead tuples / bloat statistics (MVCC / VACUUM lab)
CREATE EXTENSION IF NOT EXISTS pgstattuple;
-- Row-level locks stored in tuple headers (lock lab)
CREATE EXTENSION IF NOT EXISTS pgrowlocks;
-- What is currently cached in shared_buffers
CREATE EXTENSION IF NOT EXISTS pg_buffercache;
-- Decode WAL records from SQL (WAL lab)
CREATE EXTENSION IF NOT EXISTS pg_walinspect;

DO $$
BEGIN
  EXECUTE format('COMMENT ON DATABASE %I IS %L',
                 current_database(), 'PostgreSQL lab - e-commerce sample database');
END $$;
