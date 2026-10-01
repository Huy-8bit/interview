-- =============================================================================
-- Lab 40 · Partition pruning: scan only the relevant partitions — OPTIMIZE · Strategy A
-- Strategy A: Range partitioning by month
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

-- What / why:
-- A partitioned table is a set of tables with non-overlapping ranges of the
-- partition key. When the WHERE clause constrains created_at, the planner removes
-- the partitions that cannot match ('pruning') before execution - or during
-- execution when the value is only known then (parameter, subquery).

-- Partitioned copy: one partition per month (2025-01 .. 2026-09)
CREATE TABLE lab_orders_part (
  id bigint NOT NULL, user_id bigint NOT NULL, status order_status NOT NULL,
  total_amount numeric(12,2) NOT NULL, created_at timestamptz NOT NULL
) PARTITION BY RANGE (created_at);

DO $$
DECLARE m date := '2025-01-01';
BEGIN
  WHILE m < '2026-10-01' LOOP
    EXECUTE format('CREATE TABLE %I PARTITION OF lab_orders_part FOR VALUES FROM (%L) TO (%L)',
                   'lab_orders_part_' || to_char(m, 'YYYY_MM'), m, (m + interval '1 month')::date);
    m := (m + interval '1 month')::date;
  END LOOP;
END $$;

INSERT INTO lab_orders_part SELECT * FROM lab_orders_flat;
ANALYZE lab_orders_part;

SELECT c.relname AS partition, pg_get_expr(c.relpartbound, c.oid) AS bounds, c.reltuples::bigint AS rows
FROM pg_inherits i JOIN pg_class c ON c.oid = i.inhrelid
WHERE i.inhparent = 'lab_orders_part'::regclass ORDER BY c.relname;

-- Undo only this strategy:
-- DROP TABLE IF EXISTS lab_orders_part;   -- drops all its partitions

-- Next: run 03_after.sql, compare with 01_before.sql, then 05_reset.sql.
