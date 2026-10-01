-- =============================================================================
-- Lab 32 · Planner statistics: n_distinct, MCV, histogram, correlation — OPTIMIZE · Strategy A
-- Strategy A: Bigger sample for one column: SET STATISTICS 1000 + ANALYZE
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

-- What / why:
-- ANALYZE reads a random sample of 300 x statistics_target rows (30,000 with the
-- default 100). n_distinct is extrapolated from that sample, which underestimates
-- columns with millions of values. A larger target = larger sample, more MCVs and
-- histogram buckets - and a slower ANALYZE and bigger pg_statistic.

ALTER TABLE orders ALTER COLUMN user_id SET STATISTICS 1000;
ANALYZE orders;

-- Check what was created / changed:
SELECT attname, null_frac, n_distinct, array_length(most_common_vals::text::text[], 1) AS n_mcv,
       array_length(histogram_bounds::text::text[], 1) AS n_histogram_bounds, round(correlation::numeric, 3) AS correlation
FROM pg_stats WHERE tablename = 'orders' AND attname IN ('user_id', 'status', 'total_amount', 'created_at')
ORDER BY attname;

-- Undo only this strategy:
-- ALTER TABLE orders ALTER COLUMN user_id SET STATISTICS -1;

-- Next: run 03_after.sql, compare with 01_before.sql, then 05_reset.sql.
