-- =============================================================================
-- Solution 01 · Find a customer by the last digits of the phone number
-- Ends with a reset: the database is back at its baseline.
-- =============================================================================

-- WHY THE ORIGINAL IS SLOW / WHAT CHANGES
-- A leading % makes any B-tree useless (Seq Scan of 5M rows). Reverse the string: the suffix
-- becomes a prefix. An expression index on reverse(phone) with text_pattern_ops (byte order,
-- independent of the en_US collation) turns LIKE 'prefix%' into an index range scan.
-- Alternative: a pg_trgm GIN index (bigger, also handles '%middle%').

-- 1) Optimization
CREATE INDEX ix_lab99_c01_phone_reversed ON users (reverse(phone) text_pattern_ops);

-- 2) The rewritten query
EXPLAIN (ANALYZE, BUFFERS)
SELECT id, username, phone FROM users WHERE reverse(phone) LIKE reverse('523-1035') || '%';

-- (the original query with the new index, for comparison)
EXPLAIN (ANALYZE, BUFFERS)
SELECT id, username, phone FROM users WHERE phone LIKE '%523-1035';

-- 3) Reset
DROP INDEX IF EXISTS ix_lab99_c01_phone_reversed;
RESET ALL;

ANALYZE users;
SELECT count(*) AS lab99_indexes_left FROM pg_indexes WHERE indexname LIKE 'ix\_lab99\_c01%';   -- 0

