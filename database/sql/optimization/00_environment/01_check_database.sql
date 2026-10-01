-- =============================================================================
-- 00_environment / 01 · Which server am I on?
-- Run on PRIMARY (localhost:5432) or REPLICA (localhost:5433), database ecommerce.
-- =============================================================================

SELECT version();

SELECT current_database()                     AS database,
       current_user                           AS "user",
       pg_is_in_recovery()                    AS is_replica,     -- false = primary (labs that write must run here)
       current_setting('cluster_name')        AS node,
       pg_size_pretty(pg_database_size(current_database())) AS database_size,
       now() - pg_postmaster_start_time()     AS uptime;

-- Extensions used by the labs (installed by postgres/primary/init/02-extensions.sql).
-- The labs never CREATE/DROP extensions, so these must always be present.
SELECT extname, extversion FROM pg_extension ORDER BY extname;

-- Which dataset profile is loaded? (scripts/generate-data.sh small | default | 5m)
SELECT id, status,
       settings ->> 'num_users'       AS num_users,
       settings ->> 'num_orders'      AS num_orders,
       settings ->> 'num_order_items' AS num_order_items,
       settings ->> 'seed'            AS seed,
       finished_at
FROM data_generator_runs
ORDER BY id DESC
LIMIT 3;
