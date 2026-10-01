-- =============================================================================
-- Solution 13 · Find a payment by its transaction id
-- Ends with a reset: the database is back at its baseline.
-- =============================================================================

-- WHY THE ORIGINAL IS SLOW / WHAT CHANGES
-- Casting the uuid COLUMN to text hides it from uq_payments_transaction_id. Compare in the
-- column's type: the untyped literal (or an explicit ::uuid) is converted once, and the unique
-- index answers with a single lookup. No DDL needed.

-- 2) The rewritten query
EXPLAIN (ANALYZE, BUFFERS)
SELECT id, order_id, amount, status
FROM payments
WHERE transaction_id = '0000002a-0000-4000-8000-000000594283'::uuid;

-- 3) Reset
-- no objects created
RESET ALL;

