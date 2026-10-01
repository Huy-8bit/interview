-- =============================================================================
-- Lab 01 · Seq Scan vs Index Scan — OPTIMIZE · Strategy A
-- Strategy A: B-tree index on users(phone)
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

-- What / why:
-- A B-tree keeps the phone values sorted, with a pointer (TID = page, slot)
-- to each heap row. An equality lookup walks root -> internal -> leaf
-- (3-4 pages), then fetches exactly the heap page(s) holding the match.

CREATE INDEX ix_lab01_users_phone ON users (phone);

-- Check what was created / changed:
SELECT pg_size_pretty(pg_relation_size('ix_lab01_users_phone')) AS index_size,
       pg_size_pretty(pg_relation_size('users'))                AS table_size;
-- B-tree depth: level of the root page (0 = root is a leaf)
SELECT level AS root_level, level + 1 AS pages_per_lookup_down_the_tree
FROM bt_metap('ix_lab01_users_phone');

-- Undo only this strategy:
-- DROP INDEX IF EXISTS ix_lab01_users_phone;

-- Next: run 03_after.sql, compare with 01_before.sql, then 05_reset.sql.
