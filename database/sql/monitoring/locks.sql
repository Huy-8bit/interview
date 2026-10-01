-- =============================================================================
-- Locks: who is blocked, who is blocking, and on what.
-- Reproduce a blocking situation with docs/transaction-lab.md, then run these
-- from a THIRD DBeaver connection.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Blocked sessions and the sessions blocking them (pg_blocking_pids)
-- -----------------------------------------------------------------------------
SELECT blocked.pid                          AS blocked_pid,
       blocked.usename                      AS blocked_user,
       now() - blocked.query_start          AS blocked_for,
       left(blocked.query, 100)             AS blocked_query,
       blocking.pid                         AS blocking_pid,
       blocking.state                       AS blocking_state,       -- often 'idle in transaction'
       now() - blocking.xact_start          AS blocking_xact_age,
       left(blocking.query, 100)            AS blocking_last_query
FROM pg_stat_activity AS blocked
JOIN LATERAL unnest(pg_blocking_pids(blocked.pid)) AS b(pid) ON true
JOIN pg_stat_activity AS blocking ON blocking.pid = b.pid
ORDER BY blocked_for DESC;

-- -----------------------------------------------------------------------------
-- 2. Blocking TREE: root blockers first, with everything waiting behind them
-- -----------------------------------------------------------------------------
WITH RECURSIVE
edges AS (
  SELECT a.pid AS waiter, unnest(pg_blocking_pids(a.pid)) AS holder
  FROM pg_stat_activity a
),
roots AS (
  SELECT DISTINCT holder AS pid FROM edges
  WHERE holder NOT IN (SELECT waiter FROM edges)
),
tree AS (
  SELECT r.pid, 0 AS depth, ARRAY[r.pid] AS path FROM roots r
  UNION ALL
  SELECT e.waiter, t.depth + 1, t.path || e.waiter
  FROM tree t JOIN edges e ON e.holder = t.pid
  WHERE NOT e.waiter = ANY (t.path)
)
SELECT repeat('    ', t.depth) || t.pid AS pid_tree,
       a.state, a.wait_event_type, a.wait_event,
       now() - a.xact_start AS xact_age,
       left(a.query, 100)   AS query
FROM tree t JOIN pg_stat_activity a ON a.pid = t.pid
ORDER BY t.path;

-- -----------------------------------------------------------------------------
-- 3. Every lock held or awaited on user tables / rows / transactions
-- -----------------------------------------------------------------------------
SELECT l.pid,
       a.usename,
       l.locktype,               -- relation | tuple | transactionid | virtualxid | advisory ...
       l.relation::regclass AS relation,
       l.page, l.tuple,          -- for locktype = tuple
       l.transactionid,          -- row locks are mostly visible as "wait for that xid to finish"
       l.mode,                   -- AccessShareLock, RowExclusiveLock, ShareLock, ExclusiveLock, AccessExclusiveLock...
       l.granted,                -- false = waiting
       l.waitstart,
       left(a.query, 80) AS query
FROM pg_locks l
JOIN pg_stat_activity a ON a.pid = l.pid
WHERE a.datname = current_database()
  AND l.pid <> pg_backend_pid()
ORDER BY l.granted, l.pid, l.locktype;

-- -----------------------------------------------------------------------------
-- 4. Lock summary per table
-- -----------------------------------------------------------------------------
SELECT relation::regclass AS relation, mode, granted, count(*)
FROM pg_locks
WHERE locktype = 'relation' AND database = (SELECT oid FROM pg_database WHERE datname = current_database())
GROUP BY 1, 2, 3
ORDER BY 1, 2;

-- -----------------------------------------------------------------------------
-- 5. [PRIMARY] Row-level locks. Row locks are NOT stored in pg_locks (that would
--    not scale); they live in the tuple header (xmax + infomask bits).
--    pgrowlocks decodes them - it reads the whole table, so use it on small ones.
-- -----------------------------------------------------------------------------
SELECT * FROM pgrowlocks('products');

-- Same idea without the extension: rows I cannot lock right now are locked by someone
SELECT id FROM products
WHERE id <= 20
  AND id NOT IN (SELECT id FROM products WHERE id <= 20 FOR UPDATE SKIP LOCKED);

-- -----------------------------------------------------------------------------
-- 6. Deadlocks so far (cumulative)
-- -----------------------------------------------------------------------------
SELECT datname, deadlocks, xact_commit, xact_rollback
FROM pg_stat_database
WHERE datname = current_database();
