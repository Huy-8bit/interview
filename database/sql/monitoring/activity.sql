-- =============================================================================
-- Sessions, connections, long-running and idle-in-transaction work
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Connections by state (and how close we are to max_connections)
-- -----------------------------------------------------------------------------
SELECT coalesce(state, '(background)') AS state, backend_type, count(*)
FROM pg_stat_activity
GROUP BY 1, 2
ORDER BY 3 DESC;

SELECT count(*)                                         AS connections,
       current_setting('max_connections')::int          AS max_connections,
       round(100.0 * count(*) / current_setting('max_connections')::int, 1) AS pct_used
FROM pg_stat_activity
WHERE backend_type = 'client backend';

-- Connections per database / user / application
SELECT datname, usename, application_name, client_addr, count(*)
FROM pg_stat_activity
WHERE backend_type = 'client backend'
GROUP BY 1, 2, 3, 4
ORDER BY 5 DESC;

-- -----------------------------------------------------------------------------
-- What is running right now (excluding this session)
-- -----------------------------------------------------------------------------
SELECT pid, usename, application_name, client_addr, state,
       wait_event_type, wait_event,
       now() - xact_start  AS xact_age,
       now() - query_start AS query_age,
       left(query, 120)    AS query
FROM pg_stat_activity
WHERE backend_type = 'client backend'
  AND pid <> pg_backend_pid()
ORDER BY xact_start NULLS LAST;

-- -----------------------------------------------------------------------------
-- Long-running queries (> 30 s)
-- -----------------------------------------------------------------------------
SELECT pid, usename, now() - query_start AS runtime, wait_event_type, wait_event, left(query, 200) AS query
FROM pg_stat_activity
WHERE state = 'active'
  AND now() - query_start > interval '30 seconds'
  AND pid <> pg_backend_pid()
ORDER BY runtime DESC;

-- -----------------------------------------------------------------------------
-- Long-running TRANSACTIONS (> 1 min) - they hold snapshots and locks, and
-- stop VACUUM from removing dead tuples (see backend_xmin)
-- -----------------------------------------------------------------------------
SELECT pid, usename, state, backend_xid, backend_xmin,
       now() - xact_start AS xact_age,
       left(query, 200)   AS last_query
FROM pg_stat_activity
WHERE xact_start IS NOT NULL
  AND now() - xact_start > interval '1 minute'
  AND pid <> pg_backend_pid()
ORDER BY xact_age DESC;

-- -----------------------------------------------------------------------------
-- "idle in transaction": BEGIN was issued, then the client went quiet.
-- Classic cause of lock pile-ups and table bloat.
-- -----------------------------------------------------------------------------
SELECT pid, usename, application_name, client_addr,
       now() - xact_start   AS xact_age,
       now() - state_change AS idle_for,
       left(query, 200)     AS last_query
FROM pg_stat_activity
WHERE state IN ('idle in transaction', 'idle in transaction (aborted)')
ORDER BY idle_for DESC;

-- -----------------------------------------------------------------------------
-- The oldest snapshot holding back VACUUM (xmin horizon), cluster wide
-- -----------------------------------------------------------------------------
SELECT 'session' AS source, pid::text AS who, backend_xmin AS xmin, age(backend_xmin) AS xmin_age
FROM pg_stat_activity WHERE backend_xmin IS NOT NULL
UNION ALL
SELECT 'replication slot', slot_name, xmin, age(xmin)
FROM pg_replication_slots WHERE xmin IS NOT NULL            -- hot_standby_feedback lands here
UNION ALL
SELECT 'prepared xact', gid, transaction, age(transaction)
FROM pg_prepared_xacts
ORDER BY xmin_age DESC NULLS LAST;

-- -----------------------------------------------------------------------------
-- Cancel / kill (replace 12345 with a pid)
-- -----------------------------------------------------------------------------
-- SELECT pg_cancel_backend(12345);     -- cancel the running query, keep the session
-- SELECT pg_terminate_backend(12345);  -- close the whole connection (rolls back its transaction)

-- Safety nets you can set per session / role / database:
-- SET statement_timeout = '30s';
-- SET lock_timeout = '5s';
-- SET idle_in_transaction_session_timeout = '60s';
