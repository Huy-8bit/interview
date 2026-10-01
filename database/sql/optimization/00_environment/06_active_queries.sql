-- =============================================================================
-- 00_environment / 06 · What is running right now
-- =============================================================================

SELECT pid,
       usename                                  AS "user",
       application_name                         AS app,
       client_addr,
       state,                                   -- active / idle / idle in transaction
       wait_event_type, wait_event,             -- NULL = running on CPU
       now() - xact_start                       AS xact_duration,
       now() - query_start                      AS query_duration,
       query_start,
       backend_xmin,                            -- snapshot held (blocks VACUUM cleanup)
       left(regexp_replace(query, '\s+', ' ', 'g'), 120) AS query
FROM pg_stat_activity
WHERE backend_type = 'client backend'
  AND pid <> pg_backend_pid()
ORDER BY query_start NULLS LAST;

-- Raw view (all columns):
-- SELECT * FROM pg_stat_activity;

-- Cancel a query / close a session:
-- SELECT pg_cancel_backend(<pid>);
-- SELECT pg_terminate_backend(<pid>);
