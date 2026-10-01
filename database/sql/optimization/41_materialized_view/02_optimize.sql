-- =============================================================================
-- Lab 41 · Materialized view: precompute an expensive aggregate — OPTIMIZE · Strategy A
-- Strategy A: CREATE MATERIALIZED VIEW + unique index (for REFRESH CONCURRENTLY)
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

-- What / why:
-- A materialized view stores the RESULT of a query as a table. Reads are instant,
-- but the data is only as fresh as the last REFRESH. A unique index allows
-- REFRESH MATERIALIZED VIEW CONCURRENTLY (readers are not blocked during refresh).

CREATE MATERIALIZED VIEW mv_lab41_daily_revenue AS
SELECT (created_at AT TIME ZONE 'UTC')::date AS day,
       status,
       count(*)          AS orders,
       sum(total_amount) AS revenue
FROM orders
GROUP BY 1, 2;
CREATE UNIQUE INDEX ix_lab41_mv_daily_revenue ON mv_lab41_daily_revenue (day, status);
ANALYZE mv_lab41_daily_revenue;

-- Refresh cost: the whole query runs again (CONCURRENTLY = compute + diff + apply)
REFRESH MATERIALIZED VIEW CONCURRENTLY mv_lab41_daily_revenue;

-- Check what was created / changed:
SELECT pg_size_pretty(pg_total_relation_size('mv_lab41_daily_revenue')) AS mv_size,
       (SELECT count(*) FROM mv_lab41_daily_revenue) AS mv_rows;

-- Undo only this strategy:
-- DROP MATERIALIZED VIEW IF EXISTS mv_lab41_daily_revenue;

-- Next: run 03_after.sql, compare with 01_before.sql, then 05_reset.sql.
