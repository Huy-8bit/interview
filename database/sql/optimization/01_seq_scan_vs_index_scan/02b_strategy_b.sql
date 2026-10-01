-- =============================================================================
-- Lab 01 · Seq Scan vs Index Scan — OPTIMIZE · Strategy B
-- Strategy B: Hash index on users(phone)
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

-- Start from the baseline: run 05_reset.sql first if another strategy is still applied.

-- What / why:
-- A hash index stores a 32-bit hash of each value -> it only supports '='
-- (no ranges, no ORDER BY, no LIKE 'prefix%', no UNIQUE). Compare its size and
-- plan with the B-tree of strategy A. Since PostgreSQL 10 hash indexes are
-- WAL-logged and safe to use (they replicate to the standby).

CREATE INDEX ix_lab01_users_phone_hash ON users USING hash (phone);

-- Check what was created / changed:
SELECT pg_size_pretty(pg_relation_size('ix_lab01_users_phone_hash')) AS hash_index_size;
-- A range predicate cannot use a hash index (Seq Scan again):
EXPLAIN SELECT id FROM users WHERE phone >= '+1-377-523' AND phone < '+1-377-524';

-- Undo only this strategy:
-- DROP INDEX IF EXISTS ix_lab01_users_phone_hash;

-- Next: run 03_after.sql, compare with 01_before.sql, then 05_reset.sql.
