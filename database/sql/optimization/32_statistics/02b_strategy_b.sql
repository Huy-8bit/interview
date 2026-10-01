-- =============================================================================
-- Lab 32 · Planner statistics: n_distinct, MCV, histogram, correlation — OPTIMIZE · Strategy B
-- Strategy B: Override n_distinct manually: ALTER COLUMN ... SET (n_distinct = ...)
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

-- Start from the baseline: run 05_reset.sql first if another strategy is still applied.

-- What / why:
-- When you KNOW the ratio (here: ~2.2M distinct user_ids for 5M orders = -0.444,
-- negative = 'fraction of the row count', so it scales with the table), you can
-- pin it. ANALYZE then uses this value instead of its estimate.

ALTER TABLE orders ALTER COLUMN user_id SET (n_distinct = -0.444);
ANALYZE orders;

-- Check what was created / changed:
SELECT attname, null_frac, n_distinct, array_length(most_common_vals::text::text[], 1) AS n_mcv,
       array_length(histogram_bounds::text::text[], 1) AS n_histogram_bounds, round(correlation::numeric, 3) AS correlation
FROM pg_stats WHERE tablename = 'orders' AND attname IN ('user_id', 'status', 'total_amount', 'created_at')
ORDER BY attname;
             SELECT attname, attoptions FROM pg_attribute WHERE attrelid = 'orders'::regclass AND attname = 'user_id';

-- Undo only this strategy:
-- ALTER TABLE orders ALTER COLUMN user_id RESET (n_distinct);

-- Next: run 03_after.sql, compare with 01_before.sql, then 05_reset.sql.
